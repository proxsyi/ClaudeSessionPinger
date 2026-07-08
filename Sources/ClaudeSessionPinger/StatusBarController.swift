import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState

    init(settings: SettingsStore, stats: StatsStore, appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 560)
        self.popover = popover
        super.init()

        popover.delegate = self
        let contentView = MenuBarContentView()
            .environmentObject(settings)
            .environmentObject(stats)
            .environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: contentView)

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateButton(usage: appState.usage)

        appState.requestClosePopover = { [weak self] in
            self?.closePopover()
        }

        appState.$usage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usage in
                self?.updateButton(usage: usage)
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task { await appState.refreshUsageIfStale() }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Menu bar shows a 16x16 color-coded Claude-style starburst plus the
    /// current session usage percentage, like ClaudeUsageBar: green below
    /// 70%, yellow from 70%, red from 90%; gray while usage is unknown.
    private func updateButton(usage: ClaudeUsage?) {
        guard let button = statusItem.button else { return }
        let percent = usage?.sessionPercent
        button.image = Self.starImage(color: Self.usageColor(percent: percent))
        button.title = percent.map { " \($0)%" } ?? ""
    }

    static func usageColor(percent: Int?) -> NSColor {
        guard let percent else { return .systemGray }
        if percent < 70 { return .systemGreen }
        if percent < 90 { return .systemYellow }
        return .systemRed
    }

    /// 16x16 pixel-art starburst: eight arms drawn as hard 1-point blocks on
    /// a fixed grid for the retro look. Not a template image: the color
    /// carries the usage signal.
    private static let starPixelRows = [
        "................",
        ".......XX.......",
        ".......XX.......",
        "...X...XX...X...",
        "....X..XX..X....",
        ".....X.XX.X.....",
        "......XXXX......",
        ".XXXXXXXXXXXXXX.",
        ".XXXXXXXXXXXXXX.",
        "......XXXX......",
        ".....X.XX.X.....",
        "....X..XX..X....",
        "...X...XX...X...",
        ".......XX.......",
        ".......XX.......",
        "................"
    ]

    static func starImage(color: NSColor) -> NSImage {
        let rows = starPixelRows
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            color.setFill()
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, character) in row.enumerated() where character == "X" {
                    NSRect(x: CGFloat(columnIndex), y: CGFloat(rowIndex), width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
