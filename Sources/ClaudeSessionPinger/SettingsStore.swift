import Foundation

final class SettingsStore: ObservableObject {
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
    @Published var sessionKey: String {
        didSet {
            if sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStore.delete()
            } else {
                try? KeychainStore.save(sessionKey)
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
        sessionKey = KeychainStore.load() ?? ""
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

    var maskedSessionKey: String {
        guard sessionKey.count > 4 else { return sessionKey.isEmpty ? "" : "••••" }
        let suffix = sessionKey.suffix(4)
        return "••••••••" + suffix
    }
}
