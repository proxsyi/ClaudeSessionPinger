import Foundation

final class SettingsStore: ObservableObject {
    /// Usage-alert percentages the user can pick from in Settings.
    static let availableThresholds = [50, 75, 90, 95]
    static let defaultSessionThresholds = [75, 90]
    static let defaultWeeklyThresholds = [75, 90]

    static let defaultSlots: [ScheduleSlot] = [
        ScheduleSlot(hour: 5, minute: 0),
        ScheduleSlot(hour: 10, minute: 0),
        ScheduleSlot(hour: 15, minute: 0),
        ScheduleSlot(hour: 20, minute: 0)
    ]

    private enum Keys {
        static let organizationID = "organizationID"
        static let model = "model"
        static let message = "message"
        static let scheduleSlots = "scheduleSlots"
        static let launchAtLogin = "launchAtLogin"
        static let notifyOnFailure = "notifyOnFailure"
        static let notifyOnServiceOutage = "notifyOnServiceOutage"
        static let sessionUsageThresholds = "sessionUsageThresholds"
        static let weeklyUsageThresholds = "weeklyUsageThresholds"
        static let autoModel = "autoModel"
        static let autoUpdateEnabled = "autoUpdateEnabled"
    }

    @Published var organizationID: String {
        didSet { UserDefaults.standard.set(organizationID, forKey: Keys.organizationID) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    @Published var message: String {
        didSet { UserDefaults.standard.set(message, forKey: Keys.message) }
    }
    @Published var scheduleSlots: [ScheduleSlot] {
        didSet {
            if let data = try? JSONEncoder().encode(scheduleSlots) {
                UserDefaults.standard.set(data, forKey: Keys.scheduleSlots)
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var notifyOnFailure: Bool {
        didSet { UserDefaults.standard.set(notifyOnFailure, forKey: Keys.notifyOnFailure) }
    }
    @Published var notifyOnServiceOutage: Bool {
        didSet { UserDefaults.standard.set(notifyOnServiceOutage, forKey: Keys.notifyOnServiceOutage) }
    }
    @Published var sessionUsageThresholds: [Int] {
        didSet {
            if let data = try? JSONEncoder().encode(sessionUsageThresholds) {
                UserDefaults.standard.set(data, forKey: Keys.sessionUsageThresholds)
            }
        }
    }
    @Published var weeklyUsageThresholds: [Int] {
        didSet {
            if let data = try? JSONEncoder().encode(weeklyUsageThresholds) {
                UserDefaults.standard.set(data, forKey: Keys.weeklyUsageThresholds)
            }
        }
    }
    /// When true, the app picks the lightest Claude model it detects as
    /// available instead of using the fixed `model` slug.
    @Published var autoModel: Bool {
        didSet { UserDefaults.standard.set(autoModel, forKey: Keys.autoModel) }
    }
    /// When true, new releases are downloaded and installed automatically as
    /// soon as the daily check finds one.
    @Published var autoUpdateEnabled: Bool {
        didSet { UserDefaults.standard.set(autoUpdateEnabled, forKey: Keys.autoUpdateEnabled) }
    }
    @Published var sessionKey: String {
        didSet {
            if sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStore.delete()
            } else {
                try? KeychainStore.save(sessionKey)
            }
        }
    }
    /// The full Cookie header captured by the built-in login (every claude.ai
    /// cookie, not just sessionKey), stored in the keychain alongside the key.
    @Published var cookieHeader: String {
        didSet {
            if cookieHeader.isEmpty {
                KeychainStore.delete(account: "cookieHeader")
            } else {
                try? KeychainStore.save(cookieHeader, account: "cookieHeader")
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        organizationID = defaults.string(forKey: Keys.organizationID) ?? ""
        let storedModel = defaults.string(forKey: Keys.model) ?? ""
        model = storedModel.isEmpty ? "claude-haiku-4-5-20251001" : storedModel
        message = defaults.string(forKey: Keys.message) ?? "Say 1"
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        notifyOnFailure = defaults.object(forKey: Keys.notifyOnFailure) == nil ? true : defaults.bool(forKey: Keys.notifyOnFailure)
        notifyOnServiceOutage = defaults.object(forKey: Keys.notifyOnServiceOutage) == nil ? true : defaults.bool(forKey: Keys.notifyOnServiceOutage)
        if let data = defaults.data(forKey: Keys.sessionUsageThresholds),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            sessionUsageThresholds = decoded
        } else {
            sessionUsageThresholds = SettingsStore.defaultSessionThresholds
        }
        if let data = defaults.data(forKey: Keys.weeklyUsageThresholds),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            weeklyUsageThresholds = decoded
        } else {
            weeklyUsageThresholds = SettingsStore.defaultWeeklyThresholds
        }
        sessionKey = KeychainStore.load() ?? ""
        cookieHeader = KeychainStore.load(account: "cookieHeader") ?? ""
        autoModel = defaults.object(forKey: Keys.autoModel) == nil ? true : defaults.bool(forKey: Keys.autoModel)
        autoUpdateEnabled = defaults.object(forKey: Keys.autoUpdateEnabled) == nil ? true : defaults.bool(forKey: Keys.autoUpdateEnabled)
        if let data = defaults.data(forKey: Keys.scheduleSlots),
           let decoded = try? JSONDecoder().decode([ScheduleSlot].self, from: data),
           !decoded.isEmpty {
            scheduleSlots = decoded
        } else {
            scheduleSlots = SettingsStore.defaultSlots
        }
    }

    var isConfigured: Bool {
        !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Cookie header requests should send: the full captured login
    /// cookies when they still match the current session key, otherwise just
    /// the session key (e.g. after a manual key paste).
    var effectiveCookieHeader: String {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty, !cookieHeader.isEmpty, cookieHeader.contains(trimmedKey) {
            return cookieHeader
        }
        return "sessionKey=\(trimmedKey)"
    }

    var maskedSessionKey: String {
        guard sessionKey.count > 4 else { return sessionKey.isEmpty ? "" : "••••" }
        let suffix = sessionKey.suffix(4)
        return "••••••••" + suffix
    }
}
