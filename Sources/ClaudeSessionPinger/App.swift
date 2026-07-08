import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let stats = StatsStore()
    lazy var appState = AppState(settings: settings, stats: stats)
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var settingsShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsWindowController = SettingsWindowController(settings: settings, stats: stats, appState: appState)
        statusBarController = StatusBarController(settings: settings, stats: stats, appState: appState)
        installSettingsShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsShortcutMonitor {
            NSEvent.removeMonitor(settingsShortcutMonitor)
        }
    }

    /// Cmd+, (the standard macOS Settings shortcut) opens Settings when it's
    /// closed and closes it when it's already open, whenever this app --
    /// the menu bar popover or the Settings window itself -- is active.
    /// Only fires for that exact key combo so normal typing (e.g. a comma
    /// in the message field) is never intercepted.
    private func installSettingsShortcut() {
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.charactersIgnoringModifiers == "," else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command else { return event }
            self.appState.toggleSettingsWindow?()
            return nil
        }
    }
}

@main
struct ClaudeSessionPingerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
