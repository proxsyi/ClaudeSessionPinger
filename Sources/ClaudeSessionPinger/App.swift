import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let stats = StatsStore()
    lazy var appState = AppState(settings: settings, stats: stats)
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var settingsShortcutMonitor: Any?
    private var menuShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsWindowController = SettingsWindowController(settings: settings, stats: stats, appState: appState)
        statusBarController = StatusBarController(settings: settings, stats: stats, appState: appState)
        installSettingsShortcut()
        installMenuShortcut()
        closeStraySwiftUIWindows()
    }

    /// The SwiftUI `Settings { EmptyView() }` scene below only exists to
    /// satisfy the `App` protocol -- we drive our real Settings window from
    /// `SettingsWindowController`. Because it's the app's only SwiftUI scene,
    /// macOS can open (or restore) it as a blank "<App Name> Settings" window
    /// on launch. Close only that specific window -- its title ends in
    /// " Settings" -- so we never touch the status item's own window or the
    /// popover (both have empty titles) or our real Settings window (titled
    /// exactly "Settings"). Closing those by mistake made the menu bar item
    /// stop opening.
    private func closeStraySwiftUIWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.hasSuffix(" Settings") {
                window.close()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsShortcutMonitor {
            NSEvent.removeMonitor(settingsShortcutMonitor)
        }
        if let menuShortcutMonitor {
            NSEvent.removeMonitor(menuShortcutMonitor)
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ",":
                self.appState.toggleSettingsWindow?()
                return nil
            case "u" where self.settings.enableCommandUShortcut:
                self.appState.requestTogglePopover?()
                return nil
            default:
                return event
            }
        }
    }

    /// Command-U opens or closes the menu bar popover even while another app
    /// is active. The setting is checked at event time, so disabling it takes
    /// effect immediately without restarting Session Pinger.
    private func installMenuShortcut() {
        menuShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.settings.enableCommandUShortcut else { return }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "u" else { return }
                self.appState.requestTogglePopover?()
            }
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
