import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let stats: StatsStore
    private let appState: AppState

    init(settings: SettingsStore, stats: StatsStore, appState: AppState) {
        self.settings = settings
        self.stats = stats
        self.appState = appState
        super.init()
        appState.requestShowSettings = { [weak self] in
            self?.show()
        }
        appState.closeSettingsWindow = { [weak self] in
            self?.window?.close()
        }
        appState.toggleSettingsWindow = { [weak self] in
            self?.toggle()
        }
    }

    var isShowing: Bool {
        window != nil
    }

    /// Opens Settings if it's closed, or closes it if it's already open.
    /// Used by the Cmd+, keyboard shortcut.
    func toggle() {
        if let window {
            window.close()
        } else {
            appState.requestClosePopover?()
            show()
        }
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(stats)
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.minSize = NSSize(width: 380, height: 420)
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
