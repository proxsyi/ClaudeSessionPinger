import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellable: AnyCancellable?
    private let appState: AppState

    init(settings: SettingsStore, stats: StatsStore, appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 440)
        self.popover = popover
        super.init()

        popover.delegate = self
        let contentView = MenuBarContentView()
            .environmentObject(settings)
            .environmentObject(stats)
            .environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: contentView)

        if let button = statusItem.button {
            button.image = icon(for: appState.status)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        appState.requestClosePopover = { [weak self] in
            self?.closePopover()
        }

        cancellable = appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.statusItem.button?.image = self?.icon(for: status)
            }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func icon(for status: PingStatus) -> NSImage? {
        let symbolName: String
        switch status {
        case .idle:
            symbolName = "circle.dashed"
        case .sending:
            symbolName = "arrow.triangle.2.circlepath"
        case .success:
            symbolName = "checkmark.circle"
        case .failure:
            symbolName = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Session Pinger")
        image?.isTemplate = true
        return image
    }
}
