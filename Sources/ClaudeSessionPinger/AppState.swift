import Foundation
import AppKit
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var status: PingStatus = .idle
    @Published var lastError: String?
    @Published var nextFireDate: Date?
    @Published var availableUpdate: UpdateInfo?
    @Published var isCheckingForUpdates = false
    @Published var updateCheckError: String?
    @Published var isInstallingUpdate = false
    @Published var installUpdateError: String?
    @Published var usage: ClaudeUsage?
    @Published var usageError: String?
    @Published var isRefreshingUsage = false
    @Published var serviceStatus: ClaudeServiceStatus?

    let settings: SettingsStore
    let stats: StatsStore
    var requestClosePopover: (() -> Void)?
    var requestShowSettings: (() -> Void)?
    var closeSettingsWindow: (() -> Void)?
    var toggleSettingsWindow: (() -> Void)?
    private let scheduler = Scheduler()
    private var isPinging = false
    private var lastPingDate: Date?
    private let minimumGap: TimeInterval = 60

    init(settings: SettingsStore, stats: StatsStore) {
        self.settings = settings
        self.stats = stats
        scheduler.onFire = { [weak self] in
            Task { await self?.runScheduledPing() }
        }
        rescheduleTimer()
        requestNotificationPermission()
        NotificationCenter.default.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTimeZoneChange), name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        scheduleUpdateChecks()
        scheduleUsageRefreshes()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        updateTimer?.invalidate()
        usageTimer?.invalidate()
    }

    func rescheduleTimer() {
        scheduler.schedule(slots: settings.scheduleSlots)
        nextFireDate = scheduler.nextFireDate(slots: settings.scheduleSlots)
    }

    @objc private func handleWake() {
        rescheduleTimer()
    }

    @objc private func handleTimeZoneChange() {
        rescheduleTimer()
    }

    func pingNow() {
        Task { await runPing(manual: true) }
    }

    private func runScheduledPing() async {
        await runPing(manual: false)
    }

    private func runPing(manual: Bool) async {
        guard !isPinging else { return }
        if let last = lastPingDate, !manual, Date().timeIntervalSince(last) < minimumGap {
            return
        }
        guard settings.isConfigured else {
            status = .failure
            lastError = PingError.missingCredentials.localizedDescription
            stats.addRecord(success: false, summary: "Missing credentials")
            notifyFailureIfNeeded(message: lastError ?? "")
            rescheduleTimer()
            return
        }

        isPinging = true
        status = .sending
        lastError = nil

        let maxAttempts = 3
        var attempt = 0
        var finished = false

        while attempt < maxAttempts && !finished {
            attempt += 1
            do {
                let outcome = try await ClaudeClient.sendPing(
                    sessionKey: settings.sessionKey,
                    organizationID: settings.organizationID,
                    model: settings.model,
                    message: settings.message
                )
                lastPingDate = Date()
                status = outcome.matchedExpected ? .success : .failure
                let summary = outcome.matchedExpected ? "Got expected reply" : "Unexpected reply: \(outcome.replyText)"
                stats.addRecord(success: outcome.matchedExpected, summary: summary)
                if !outcome.matchedExpected {
                    lastError = "Claude responded, but not with the expected text."
                    notifyFailureIfNeeded(message: lastError ?? "")
                }
                rescheduleTimer()
                finished = true
            } catch let error as PingError {
                if attempt >= maxAttempts || !isRetryable(error) {
                    lastPingDate = Date()
                    status = .failure
                    lastError = error.localizedDescription
                    stats.addRecord(success: false, summary: error.localizedDescription)
                    notifyFailureIfNeeded(message: error.localizedDescription)
                    rescheduleTimer()
                    finished = true
                } else {
                    let backoffSeconds = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                }
            } catch {
                lastPingDate = Date()
                status = .failure
                lastError = error.localizedDescription
                stats.addRecord(success: false, summary: error.localizedDescription)
                notifyFailureIfNeeded(message: error.localizedDescription)
                rescheduleTimer()
                finished = true
            }
        }

        isPinging = false
    }

    private func isRetryable(_ error: PingError) -> Bool {
        switch error {
        case .network:
            return true
        case .serverError(let code, _):
            return code >= 500
        default:
            return false
        }
    }

    private var updateTimer: Timer?

    /// Checks once shortly after launch, then once a day after that.
    /// Any failure (no network, no feed configured yet, bad response) is
    /// stored in `updateCheckError` and otherwise ignored -- this never
    /// interrupts pinging or shows an alert.
    private func scheduleUpdateChecks() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self?.checkForUpdates()
        }
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60 * 24, repeats: true) { [weak self] _ in
            Task { await self?.checkForUpdates() }
        }
    }

    private var usageTimer: Timer?

    /// Fetches usage shortly after launch, then every 5 minutes, mirroring how
    /// ClaudeUsageBar keeps its numbers fresh. Failures only set `usageError`
    /// and never interrupt pinging.
    private func scheduleUsageRefreshes() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.refreshUsage()
        }
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refreshUsage() }
        }
    }

    /// Used when the popover opens: refresh only if the data is older than a
    /// minute so opening the popover shows fresh numbers without hammering
    /// the API on every click.
    func refreshUsageIfStale() async {
        if let fetched = usage?.fetchedAt, Date().timeIntervalSince(fetched) < 60 { return }
        await refreshUsage()
    }

    func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        async let statusCheck = UsageChecker.fetchServiceStatus()
        do {
            let fetched = try await UsageChecker.fetchUsage(
                sessionKey: settings.sessionKey,
                organizationID: settings.organizationID
            )
            usage = fetched
            usageError = nil
            notifyUsageThresholdsIfNeeded(for: fetched)
        } catch {
            usageError = (error as? UsageError)?.localizedDescription ?? error.localizedDescription
        }
        if let status = await statusCheck {
            notifyServiceChangeIfNeeded(newStatus: status)
            serviceStatus = status
        }
        isRefreshingUsage = false
    }

    // MARK: - Usage threshold & service status notifications

    /// Thresholds already notified for the current session window.
    private var notifiedSessionThresholds: Set<Int> = []
    /// Thresholds already notified for the current weekly window.
    private var notifiedWeeklyThresholds: Set<Int> = []
    /// Reset timestamps last seen -- when these change, a new window has
    /// started, so its thresholds may fire again.
    private var lastSessionResetsAt: Date?
    private var lastWeeklyResetsAt: Date?
    /// nil until the first status check completes, so launching during an
    /// outage never fires a spurious outage/recovery notification.
    private var lastKnownServiceOperational: Bool?

    /// Fires each user-selected usage threshold at most once per window.
    private func notifyUsageThresholdsIfNeeded(for fetched: ClaudeUsage) {
        if fetched.sessionResetsAt != lastSessionResetsAt {
            lastSessionResetsAt = fetched.sessionResetsAt
            notifiedSessionThresholds.removeAll()
        }
        if fetched.weeklyResetsAt != lastWeeklyResetsAt {
            lastWeeklyResetsAt = fetched.weeklyResetsAt
            notifiedWeeklyThresholds.removeAll()
        }
        if let percent = fetched.sessionPercent {
            for threshold in settings.sessionUsageThresholds.sorted()
            where percent >= threshold && !notifiedSessionThresholds.contains(threshold) {
                notifiedSessionThresholds.insert(threshold)
                let reset = fetched.sessionResetsAt.map { " Resets at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
                sendNotification(
                    identifier: "usage-session-\(threshold)",
                    title: "Session usage reached \(threshold)%",
                    body: "Your 5-hour session window is at \(percent)%.\(reset)"
                )
            }
        }
        if let percent = fetched.weeklyPercent {
            for threshold in settings.weeklyUsageThresholds.sorted()
            where percent >= threshold && !notifiedWeeklyThresholds.contains(threshold) {
                notifiedWeeklyThresholds.insert(threshold)
                let reset = fetched.weeklyResetsAt.map { " Resets \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
                sendNotification(
                    identifier: "usage-weekly-\(threshold)",
                    title: "Weekly usage reached \(threshold)%",
                    body: "Your 7-day window is at \(percent)%.\(reset)"
                )
            }
        }
    }

    /// Notifies when Claude services go down or recover, once per transition.
    private func notifyServiceChangeIfNeeded(newStatus: ClaudeServiceStatus) {
        defer { lastKnownServiceOperational = newStatus.operational }
        guard settings.notifyOnServiceOutage,
              let wasOperational = lastKnownServiceOperational,
              wasOperational != newStatus.operational else { return }
        if newStatus.operational {
            sendNotification(
                identifier: "service-recovered",
                title: "Claude services recovered",
                body: "All Claude services are operational again."
            )
        } else {
            sendNotification(
                identifier: "service-outage",
                title: "Claude service issue",
                body: newStatus.message
            )
        }
    }

    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        updateCheckError = nil
        let currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        let result = await UpdateChecker.check(currentVersion: currentVersion)
        switch result {
        case .upToDate:
            availableUpdate = nil
        case .updateAvailable(let info):
            availableUpdate = info
        case .failed(let message):
            availableUpdate = nil
            updateCheckError = message
        }
        isCheckingForUpdates = false
    }

    /// Downloads the available update's app bundle, swaps it in for this
    /// running app, and relaunches it. On success this method never visibly
    /// returns -- `Updater` terminates the app partway through the install.
    func installUpdate() {
        guard let update = availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        installUpdateError = nil
        Task {
            do {
                try await Updater.downloadAndInstall(update)
            } catch {
                self.isInstallingUpdate = false
                self.installUpdateError = (error as? UpdaterError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    private var runningInsideProperAppBundle: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") != nil
    }

    private func requestNotificationPermission() {
        guard runningInsideProperAppBundle else {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyFailureIfNeeded(message: String) {
        guard settings.notifyOnFailure else { return }
        sendNotification(identifier: UUID().uuidString, title: "Session ping failed", body: message)
    }

    /// Shared local-notification helper. Stable identifiers let the system
    /// coalesce repeats of the same alert instead of stacking duplicates.
    private func sendNotification(identifier: String, title: String, body: String) {
        guard runningInsideProperAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
