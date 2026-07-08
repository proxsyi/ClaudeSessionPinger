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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        updateTimer?.invalidate()
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
        guard settings.notifyOnFailure, runningInsideProperAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Session ping failed"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
