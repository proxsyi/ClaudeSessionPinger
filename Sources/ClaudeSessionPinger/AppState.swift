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
    /// Model slugs detected as available for this account (empty until fetched).
    @Published var availableModels: [String] = []
    /// The model the last successful ping actually used.
    @Published var activeModel: String?
    /// Result line for the Settings "Send test notification" button.
    @Published var notificationTestStatus: String?

    let settings: SettingsStore
    let stats: StatsStore
    var requestClosePopover: (() -> Void)?
    var requestTogglePopover: (() -> Void)?
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
        let candidates = modelCandidates()
        var modelIndex = 0

        while attempt < maxAttempts && !finished {
            attempt += 1
            let modelToUse = candidates[min(modelIndex, candidates.count - 1)]
            do {
                let outcome = try await ClaudeClient.sendPing(
                    sessionKey: settings.sessionKey,
                    organizationID: settings.organizationID,
                    model: modelToUse,
                    message: settings.message,
                    conversationID: settings.conversationID,
                    cookieHeader: settings.effectiveCookieHeader
                )
                settings.conversationID = outcome.conversationID
                activeModel = modelToUse
                lastPingDate = Date()
                status = outcome.matchedExpected ? .success : .failure
                let summary = outcome.matchedExpected ? "Got expected reply" : "Unexpected reply: \(outcome.replyText)"
                stats.addRecord(success: outcome.matchedExpected, summary: summary)
                if outcome.matchedExpected && settings.notifySessionStarted {
                    sendNotification(
                        identifier: "session-started",
                        title: "New Claude session started",
                        body: manual
                            ? "Your manual ping started a new session."
                            : "Session Pinger started a new session."
                    )
                }
                if !outcome.matchedExpected {
                    lastError = "Claude responded, but not with the expected text."
                    notifyFailureIfNeeded(message: lastError ?? "")
                }
                rescheduleTimer()
                finished = true
            } catch let error as PingError {
                if isModelUnavailable(error), modelIndex + 1 < candidates.count {
                    // The account can't use this model right now -- move on to
                    // the next available one without burning a retry attempt.
                    modelIndex += 1
                    attempt -= 1
                    continue
                }
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

    /// Try the user's selected model first, then detected and known fallbacks
    /// from lightest to heaviest if Claude rejects that model.
    private func modelCandidates() -> [String] {
        let selected = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPool = (availableModels + UsageChecker.fallbackModels)
            .sorted { modelRank($0) < modelRank($1) }
        var candidates = selected.isEmpty ? [] : [selected]
        for model in fallbackPool where !candidates.contains(model) {
            candidates.append(model)
        }
        return candidates
    }

    private func modelRank(_ slug: String) -> Int {
        if slug.contains("haiku") { return 0 }
        if slug.contains("sonnet") { return 1 }
        if slug.contains("opus") { return 2 }
        return 3
    }

    /// True when the server rejected the request in a way that points at the
    /// model slug itself (unknown/retired/unavailable model), so trying the
    /// next candidate makes sense.
    private func isModelUnavailable(_ error: PingError) -> Bool {
        if case .serverError(let code, let body) = error {
            return (400...499).contains(code) && body.lowercased().contains("model")
        }
        return false
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
            let previousUsage = usage
            let fetched = try await UsageChecker.fetchUsage(
                sessionKey: settings.sessionKey,
                organizationID: settings.organizationID,
                cookieHeader: settings.effectiveCookieHeader
            )
            usage = fetched
            usageError = nil
            notifyUsageThresholdsIfNeeded(for: fetched)
            handleSessionAvailability(previous: previousUsage, current: fetched)
        } catch {
            usageError = (error as? UsageError)?.localizedDescription ?? error.localizedDescription
        }
        if let status = await statusCheck {
            notifyServiceChangeIfNeeded(newStatus: status)
            serviceStatus = status
        }
        let models = await UsageChecker.fetchAvailableModels(
            sessionKey: settings.sessionKey,
            organizationID: settings.organizationID,
            cookieHeader: settings.effectiveCookieHeader
        )
        if !models.isEmpty {
            availableModels = models.sorted { modelRank($0) < modelRank($1) }
        }
        isRefreshingUsage = false
    }

    // MARK: - Usage threshold & service status notifications

    private var sessionAvailabilityBaselined = false

    private func handleSessionAvailability(previous: ClaudeUsage?, current: ClaudeUsage) {
        defer { sessionAvailabilityBaselined = true }
        guard sessionAvailabilityBaselined, let previous else { return }

        let becameAvailable = (previous.sessionPercent ?? 0) >= 100 && (current.sessionPercent ?? 100) < 100
        let resetRolledForward: Bool
        if let oldReset = previous.sessionResetsAt, let newReset = current.sessionResetsAt {
            resetRolledForward = oldReset <= Date() && newReset.timeIntervalSince(oldReset) > resetJitterTolerance
        } else {
            resetRolledForward = false
        }
        guard becameAvailable || resetRolledForward else { return }

        if settings.notifySessionAvailable {
            sendNotification(
                identifier: "session-available",
                title: "A new Claude session is available",
                body: "Your previous 5-hour window reset."
            )
        }

        guard settings.autoStartAvailableSessions, !isPinging else { return }
        let scheduledSoon = nextFireDate.map { abs($0.timeIntervalSinceNow) <= 10 * 60 } ?? false
        guard !scheduledSoon else { return }
        Task { await runPing(manual: false) }
    }

    /// Thresholds already notified for the current session window.
    private var notifiedSessionThresholds: Set<Int> = []
    /// Thresholds already notified for the current weekly window.
    private var notifiedWeeklyThresholds: Set<Int> = []
    /// Reset timestamps last seen -- when these move by more than the jitter
    /// tolerance, a new window has started and thresholds may fire again.
    private var lastSessionResetsAt: Date?
    private var lastWeeklyResetsAt: Date?
    /// False until the first successful usage fetch of this run. That first
    /// fetch only records which thresholds are already crossed -- it never
    /// alerts, so relaunching the app can't re-alert limits hit earlier.
    private var usageBaselined = false
    /// The server recomputes reset timestamps on every poll, so two reads of
    /// the same window can differ by a few seconds. Only a shift bigger than
    /// this counts as a genuinely new window.
    private let resetJitterTolerance: TimeInterval = 120

    private func isNewWindow(_ new: Date, comparedTo old: Date?) -> Bool {
        guard let old else { return true }
        return abs(new.timeIntervalSince(old)) > resetJitterTolerance
    }
    /// nil until the first status check completes, so launching during an
    /// outage never fires a spurious outage/degraded/recovery notification.
    private var lastKnownServiceLevel: ClaudeServiceStatus.Level?

    /// Fires each user-selected usage threshold at most once per window.
    /// Guards against the two big false-alert sources: relaunching the app
    /// (the first fetch baselines silently) and server-side jitter in the
    /// reset timestamps (small shifts don't count as a new window).
    private func notifyUsageThresholdsIfNeeded(for fetched: ClaudeUsage) {
        if let sessionResets = fetched.sessionResetsAt {
            if isNewWindow(sessionResets, comparedTo: lastSessionResetsAt) {
                notifiedSessionThresholds.removeAll()
            }
            lastSessionResetsAt = sessionResets
        }
        if let weeklyResets = fetched.weeklyResetsAt {
            if isNewWindow(weeklyResets, comparedTo: lastWeeklyResetsAt) {
                notifiedWeeklyThresholds.removeAll()
            }
            lastWeeklyResetsAt = weeklyResets
        }

        // Self-healing: usage only rises within a window, so a percent now
        // sitting well below an already-notified threshold means the window
        // really did reset even if the timestamps never showed it.
        if let percent = fetched.sessionPercent {
            notifiedSessionThresholds = notifiedSessionThresholds.filter { $0 <= percent + 10 }
        }
        if let percent = fetched.weeklyPercent {
            notifiedWeeklyThresholds = notifiedWeeklyThresholds.filter { $0 <= percent + 10 }
        }

        let crossedSession = settings.sessionUsageThresholds.sorted().filter { threshold in
            (fetched.sessionPercent ?? 0) >= threshold && !notifiedSessionThresholds.contains(threshold)
        }
        let crossedWeekly = settings.weeklyUsageThresholds.sorted().filter { threshold in
            (fetched.weeklyPercent ?? 0) >= threshold && !notifiedWeeklyThresholds.contains(threshold)
        }
        notifiedSessionThresholds.formUnion(crossedSession)
        notifiedWeeklyThresholds.formUnion(crossedWeekly)

        // First successful fetch after launch: record what's already crossed
        // without alerting -- those limits were hit before this run.
        if !usageBaselined {
            usageBaselined = true
            return
        }

        if let percent = fetched.sessionPercent {
            for threshold in crossedSession {
                let reset = fetched.sessionResetsAt.map { " Resets at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
                sendNotification(
                    identifier: "usage-session-\(threshold)",
                    title: "Session usage reached \(threshold)%",
                    body: "Your 5-hour session window is at \(percent)%.\(reset)"
                )
            }
        }
        if let percent = fetched.weeklyPercent {
            for threshold in crossedWeekly {
                let reset = fetched.weeklyResetsAt.map { " Resets \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
                sendNotification(
                    identifier: "usage-weekly-\(threshold)",
                    title: "Weekly usage reached \(threshold)%",
                    body: "Your 7-day window is at \(percent)%.\(reset)"
                )
            }
        }
    }

    /// Notifies when Claude services go down, degrade, or recover -- once
    /// per level transition, gated by the user's notification toggles.
    private func notifyServiceChangeIfNeeded(newStatus: ClaudeServiceStatus) {
        defer { lastKnownServiceLevel = newStatus.level }
        guard let previous = lastKnownServiceLevel, previous != newStatus.level else { return }
        switch newStatus.level {
        case .outage:
            guard settings.notifyOnServiceOutage else { return }
            sendNotification(
                identifier: "service-outage",
                title: "Claude services are down",
                body: newStatus.message
            )
        case .degraded:
            guard settings.notifyOnServiceDegraded else { return }
            sendNotification(
                identifier: "service-degraded",
                title: "Claude services are performing poorly",
                body: newStatus.message
            )
        case .operational:
            // Recovery matters to anyone who saw either alert above.
            guard settings.notifyOnServiceOutage || settings.notifyOnServiceDegraded else { return }
            sendNotification(
                identifier: "service-recovered",
                title: "Claude services recovered",
                body: "All Claude services are operational again."
            )
        }
    }

    /// Versions the auto-updater has already tried to install this run.
    private var autoUpdateAttemptedVersions: Set<String> = []

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
            // Auto-update: install the new release as soon as it's seen, but
            // only try each version once so a failing install can't loop.
            if settings.autoUpdateEnabled && !autoUpdateAttemptedVersions.contains(info.version) {
                autoUpdateAttemptedVersions.insert(info.version)
                installUpdate()
            }
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

    /// Sends a test notification so delivery can be verified from Settings.
    /// Requests permission on the spot if it was never granted, and reports
    /// exactly why nothing appeared otherwise.
    func sendTestNotification() {
        notificationTestStatus = nil
        guard runningInsideProperAppBundle else {
            notificationTestStatus = "Run the installed app bundle to test notifications."
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notificationSettings in
            let status = notificationSettings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .denied:
                    self.notificationTestStatus = "Notifications are turned off for Session Pinger. Turn them on in System Settings > Notifications > Session Pinger, then test again."
                case .notDetermined:
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        if granted {
                            self.deliverTestNotification()
                        } else {
                            self.notificationTestStatus = "Permission wasn't granted, so macOS won't show notifications."
                        }
                    } catch {
                        self.notificationTestStatus = "macOS couldn't request notification permission: \(error.localizedDescription)"
                    }
                default:
                    self.deliverTestNotification()
                }
            }
        }
    }

    /// Sends the actual test alert and reports delivery errors instead of
    /// failing silently.
    private func deliverTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.body = "Notifications are working."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "test-notification", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.notificationTestStatus = "macOS rejected the notification: \(error.localizedDescription)"
                } else {
                    self.notificationTestStatus = "Test notification sent -- check the top-right of your screen."
                }
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
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func notifyFailureIfNeeded(message: String) {
        guard settings.notifyOnFailure else { return }
        // Stable identifier: repeated failures replace the previous alert
        // instead of stacking a pile of duplicates.
        sendNotification(identifier: "ping-failure", title: "Session ping failed", body: message)
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
