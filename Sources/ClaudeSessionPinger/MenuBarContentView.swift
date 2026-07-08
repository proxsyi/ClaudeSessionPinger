import SwiftUI
import AppKit
import Combine

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var stats: StatsStore
    @State private var now = Date()

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let update = appState.availableUpdate {
                updateBanner(update)
                    .padding(12)
                    .glassPanel(tint: .green)
            }
            countdownSection
                .padding(12)
                .glassPanel(tint: ClaudeTheme.accent)
            statsSection
                .padding(12)
                .glassPanel()
            actionsSection
        }
        .claudeGlassContainer(spacing: 12)
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial)
        .onReceive(clockTimer) { value in
            now = value
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text("Session Pinger")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ClaudeTheme.textPrimary)
            Spacer()
        }
    }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                Text("Version \(update.version) is available")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTheme.textPrimary)
            }
            if let notes = update.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textSecondary)
                    .lineLimit(2)
            }
            Button("Download update") {
                if let url = URL(string: update.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .claudeGhostButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle:
            return .gray
        case .sending:
            return .yellow
        case .success:
            return ClaudeTheme.accent
        case .failure:
            return .red
        }
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next session in")
                .font(.system(size: 11))
                .foregroundColor(ClaudeTheme.textSecondary)
            Text(countdownText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(ClaudeTheme.textPrimary)
            if let next = appState.nextFireDate {
                Text(next.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countdownText: String {
        guard let next = appState.nextFireDate else { return "Not scheduled" }
        let remaining = max(0, next.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Success rate")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textSecondary)
                Spacer()
                Text(successRateText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTheme.textPrimary)
            }
            HStack {
                Text("Last result")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textSecondary)
                Spacer()
                Text(lastResultText)
                    .font(.system(size: 12))
                    .foregroundColor(ClaudeTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let error = appState.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var successRateText: String {
        guard stats.totalCount > 0 else { return "No pings yet" }
        return "\(stats.successCount)/\(stats.totalCount) (\(Int(stats.successRate * 100))%)"
    }

    private var lastResultText: String {
        guard let last = stats.lastRecord else { return "—" }
        return last.summary
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button(action: { appState.pingNow() }) {
                Text(appState.status == .sending ? "Sending…" : "Ping now")
            }
            .claudePrimaryButton()
            .disabled(appState.status == .sending)

            HStack {
                Button("Settings") {
                    appState.requestShowSettings?()
                    appState.requestClosePopover?()
                }
                .claudeGhostButton()
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .claudeGhostButton()
            }
        }
    }
}
