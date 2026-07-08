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
            usageSection
                .padding(12)
                .glassPanel()
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
        .frame(width: 320)
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
            if let installError = appState.installUpdateError {
                Text(installError)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(appState.isInstallingUpdate ? "Installing…" : "Install & Restart") {
                    appState.installUpdate()
                }
                .claudeGhostButton()
                .disabled(appState.isInstallingUpdate)
                Button("View release") {
                    if let url = URL(string: update.releasePageURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .claudeGhostButton()
                .disabled(appState.isInstallingUpdate)
            }
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

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ClaudeTheme.textPrimary)

            usageRow(
                title: "Session (5 hour)",
                percent: appState.usage?.sessionPercent,
                resetText: sessionResetText
            )
            usageRow(
                title: "Weekly (7 day)",
                percent: appState.usage?.weeklyPercent,
                resetText: weeklyResetText
            )

            if let error = appState.usageError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            serviceStatusRow

            HStack {
                Text(lastUpdatedText)
                    .font(.system(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
                Spacer()
                Button(appState.isRefreshingUsage ? "Refreshing…" : "Refresh") {
                    Task { await appState.refreshUsage() }
                }
                .claudeGhostButton()
                .disabled(appState.isRefreshingUsage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageRow(title: String, percent: Int?, resetText: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTheme.textPrimary)
                Spacer()
                if let resetText {
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundColor(ClaudeTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            usageBar(percent: percent)
            Text(percent.map { "\($0)% used" } ?? "No data yet")
                .font(.system(size: 11))
                .foregroundColor(ClaudeTheme.textSecondary)
        }
    }

    private func usageBar(percent: Int?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(usageBarColor(percent: percent))
                    .frame(width: geo.size.width * CGFloat(min(max(percent ?? 0, 0), 100)) / 100)
            }
        }
        .frame(height: 5)
    }

    private func usageBarColor(percent: Int?) -> Color {
        guard let percent else { return .gray }
        if percent < 70 { return .green }
        if percent < 90 { return .yellow }
        return .red
    }

    private var serviceStatusRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(serviceStatusColor)
                    .frame(width: 8, height: 8)
                Text(appState.serviceStatus?.message ?? "Checking Claude service status…")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(serviceStatusDetail)
                .font(.system(size: 10))
                .foregroundColor(ClaudeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var serviceStatusColor: Color {
        guard let status = appState.serviceStatus else { return .gray }
        return status.operational ? .green : .orange
    }

    private var serviceStatusDetail: String {
        var text = "Tracks claude.ai, Claude Console, Claude API, Claude Code +1"
        if let checked = appState.serviceStatus?.checkedAt {
            text += " · checked \(relativeTimeText(since: checked))"
        }
        return text
    }

    private func relativeTimeText(since date: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60)h ago"
    }

    private var sessionResetText: String? {
        guard let date = appState.usage?.sessionResetsAt else { return nil }
        return "Resets at \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var weeklyResetText: String? {
        guard let date = appState.usage?.weeklyResetsAt else { return nil }
        let day = date.formatted(.dateTime.day().month(.abbreviated).year())
        let time = date.formatted(date: .omitted, time: .shortened)
        return "Resets on \(day) at \(time)"
    }

    private var lastUpdatedText: String {
        guard let fetched = appState.usage?.fetchedAt else { return "Not updated yet" }
        return "Last updated: \(fetched.formatted(date: .omitted, time: .shortened))"
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
