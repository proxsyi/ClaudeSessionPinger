import SwiftUI
import AppKit

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case usage = "Usage"
    case alerts = "Alerts"
    case app = "App"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .usage: return "chart.bar.fill"
        case .alerts: return "bell.fill"
        case .app: return "gearshape.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var stats: StatsStore

    @State private var sessionKeyInput = ""
    @State private var organizationID = ""
    @State private var model = ""
    @State private var message = ""
    @State private var slots: [ScheduleSlot] = []
    @State private var launchAtLogin = false
    @State private var notifyOnFailure = true
    @State private var notifyOnServiceOutage = true
    @State private var notifyOnServiceDegraded = true
    @State private var sessionThresholds: Set<Int> = []
    @State private var weeklyThresholds: Set<Int> = []
    @State private var showSessionBar = true
    @State private var showWeeklyBar = true
    @State private var showFable5Bar = false
    @State private var showNextPossibleCountdown = true
    @State private var showScheduledCountdown = true
    @State private var countdownFocus: CountdownFocus = .nextPossible
    @State private var notifySessionAvailable = true
    @State private var notifySessionStarted = true
    @State private var autoStartAvailableSessions = false
    @State private var enableCommandUShortcut = true
    @State private var preferClearGlass = true
    @State private var selectedTab: SettingsTab = .general
    @State private var autoUpdate = true
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showingLogin = false
    @State private var loginCaptured = false
    @State private var isFetchingOrganization = false
    @Namespace private var tabSelectionAnimation

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                tabContent
                    .id(selectedTab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .padding(20)
            }
            .animation(.easeInOut(duration: 0.32), value: selectedTab)
            .scrollIndicators(.hidden)
            .clipped()

            Divider()

            footer
                .background(WindowGlassBackground(clearGlass: settings.preferClearGlass))
        }
        .frame(width: 460, height: 600)
        .background(WindowGlassBackground(clearGlass: settings.preferClearGlass).ignoresSafeArea())
        .onAppear {
            loadCurrentValues()
            appState.requestSaveAndCloseSettings = {
                save(showPopoverAfterClose: true)
            }
        }
        .onDisappear {
            appState.requestSaveAndCloseSettings = nil
        }
        .sheet(isPresented: $showingLogin) {
            CookieLoginSheet { sessionKey, organizationIDFromCookie, cookieHeader in
                handleLoginCapture(
                    sessionKey: sessionKey,
                    organizationIDFromCookie: organizationIDFromCookie,
                    cookieHeader: cookieHeader
                )
            }
        }
    }

    @ViewBuilder
    private var settingsTabBar: some View {
        GeometryReader { proxy in
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(SettingsTab.allCases) { tab in
                            Button {
                                selectTab(tab)
                            } label: {
                                Label(tab.rawValue, systemImage: tab.symbol)
                                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedTab == tab ? Color.white : ClaudeTheme.textSecondary)
                            .background {
                                if selectedTab == tab {
                                    Capsule(style: .continuous)
                                        .fill(Color.clear)
                                        .glassEffect(
                                            .regular.tint(ClaudeTheme.accent).interactive(),
                                            in: Capsule(style: .continuous)
                                        )
                                        .matchedGeometryEffect(id: "selected-settings-tab", in: tabSelectionAnimation)
                                }
                            }
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule(style: .continuous))
                    .glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
                    .simultaneousGesture(tabDragGesture(width: proxy.size.width))
                }
            } else {
                Picker("Settings section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(height: 42)
    }

    private func selectTab(_ tab: SettingsTab) {
        guard tab != selectedTab else { return }
        withAnimation(.easeInOut(duration: 0.32)) {
            selectedTab = tab
        }
    }

    private func tabDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let inset: CGFloat = 4
                let availableWidth = max(width - (inset * 2), 1)
                let relativeX = min(max(value.location.x - inset, 0), availableWidth - 1)
                let index = min(Int(relativeX / (availableWidth / CGFloat(SettingsTab.allCases.count))), SettingsTab.allCases.count - 1)
                selectTab(SettingsTab.allCases[index])
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedTab {
            case .general:
                accountSection.padding(14).glassPanel()
                pingSection.padding(14).glassPanel()
                activitySection.padding(14).glassPanel()
            case .usage:
                usageBarsSection.padding(14).glassPanel()
            case .alerts:
                notificationsSection.padding(14).glassPanel()
            case .app:
                appSection.padding(14).glassPanel()
                updatesSection.padding(14).glassPanel()
            }
        }
        .claudeGlassContainer()
    }

    // MARK: - Reusable rows

    /// A clean settings row: label on the left, a small switch pinned to the
    /// right edge, like System Settings. The explicit accessibility label
    /// keeps VoiceOver working despite `labelsHidden()`.
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(ClaudeTheme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ClaudeTheme.textSecondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ClaudeTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Account")

            Button(loginCaptured || !settings.sessionKey.isEmpty ? "Log in again" : "Log in with Claude") {
                showingLogin = true
            }
            .claudePrimaryButton()

            if loginCaptured {
                Text("Signed in -- session and cookies captured automatically.")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.accent)
            } else if !settings.sessionKey.isEmpty {
                caption("Using a previously captured session (\(settings.maskedSessionKey)).")
            }

            if isFetchingOrganization {
                caption("Detecting your organization ID\u{2026}")
            } else if loginCaptured && organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Couldn't detect your organization ID automatically. Open claude.ai in a browser, open Dev Tools \u{2192} Application \u{2192} Cookies, and paste the value of \"lastActiveOrg\" under Keys below.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            keysDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Collapsed by default: the organization ID and session key are captured
    /// automatically at login, so these fields exist only for manual fixes.
    private var keysDisclosure: some View {
        DisclosureGroup("Keys") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Organization ID")
                    TextField("Filled automatically on login", text: $organizationID)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Session key")
                    SecureField(settings.sessionKey.isEmpty ? "Paste sessionKey cookie" : settings.maskedSessionKey, text: $sessionKeyInput)
                        .textFieldStyle(.roundedBorder)
                    caption("Only needed if the built-in login doesn't work for your account.")
                }
                caption(settings.cookieHeader.isEmpty
                    ? "No login cookies captured yet -- use Log in with Claude above."
                    : "Full login cookies captured and stored in the keychain.")
            }
            .padding(.top, 8)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(ClaudeTheme.textSecondary)
    }

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Ping")

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Model")
                Picker("Model", selection: $model) {
                    ForEach(modelOptions, id: \.self) { slug in
                        Text(modelLabel(slug)).tag(slug)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                caption("Your choice is tried first. If Claude rejects it, the app falls back to another available model.")
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Message")
                TextField("Say 1", text: $message)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Schedule")
                ForEach(slots.indices, id: \.self) { index in
                    HStack {
                        Stepper(value: Binding(
                            get: { slots[index].hour },
                            set: { slots[index].hour = $0 }
                        ), in: 0...23) {
                            HStack(spacing: 6) {
                                Text(formattedTimeNumbers(hour: slots[index].hour, minute: slots[index].minute))
                                    .frame(width: 40, alignment: .trailing)
                                Text(timePeriod(hour: slots[index].hour))
                                    .frame(width: 22, alignment: .leading)
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ClaudeTheme.textPrimary)
                        }
                        Spacer()
                        Button(action: { slots.remove(at: index) }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add time") {
                    slots.append(ScheduleSlot(hour: 12, minute: 0))
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ClaudeTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelOptions: [String] {
        let selected = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = selected.isEmpty ? [] : [selected]
        let pool = appState.availableModels + UsageChecker.fallbackModels
        for slug in pool.sorted(by: { modelRank($0) < modelRank($1) }) where !options.contains(slug) {
            options.append(slug)
        }
        return options
    }

    private func modelRank(_ slug: String) -> Int {
        if slug.contains("haiku") { return 0 }
        if slug.contains("sonnet") { return 1 }
        if slug.contains("opus") { return 2 }
        return 3
    }

    private func modelLabel(_ slug: String) -> String {
        if slug.contains("haiku") { return "Haiku (suggested) — \(slug)" }
        if slug.contains("sonnet") { return "Sonnet — \(slug)" }
        if slug.contains("opus") { return "Opus — \(slug)" }
        return slug
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Activity")

            HStack {
                fieldLabel("Success rate")
                Spacer()
                Text(successRateText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(ClaudeTheme.textPrimary)
            }

            HStack(alignment: .firstTextBaseline) {
                fieldLabel("Last result")
                Spacer()
                Text(stats.lastRecord?.summary ?? "—")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let activeModel = appState.activeModel {
                caption("Last successful model: \(activeModel)")
            }

            caption(settings.conversationID.isEmpty
                ? "The next ping will create one dedicated Claude chat and reuse it afterward."
                : "Pings are reusing one dedicated Claude chat.")

            if !settings.conversationID.isEmpty {
                HStack {
                    Button("Open pinger chat") {
                        if let url = URL(string: "https://claude.ai/chat/\(settings.conversationID)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .claudeGhostButton()
                    Spacer()
                    Button("Start fresh chat") {
                        settings.conversationID = ""
                    }
                    .claudeGhostButton()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var successRateText: String {
        guard stats.totalCount > 0 else { return "No pings yet" }
        return "\(stats.successCount)/\(stats.totalCount) (\(Int(stats.successRate * 100))%)"
    }

    private var usageBarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Usage bars")
            toggleRow("Session (5 hour)", isOn: $showSessionBar)
            toggleRow("Weekly (7 day)", isOn: $showWeeklyBar)
            toggleRow("Fable 5 weekly", isOn: $showFable5Bar)
            caption("Choose which usage windows appear in the menu bar popover.")
            Divider()
            SectionHeader(text: "Countdown card")
            toggleRow("Next possible session", isOn: $showNextPossibleCountdown)
            toggleRow("Scheduled session", isOn: $showScheduledCountdown)
            if showNextPossibleCountdown && showScheduledCountdown {
                Picker("Main focus", selection: $countdownFocus) {
                    ForEach(CountdownFocus.allCases) { focus in
                        Text(focus.label).tag(focus)
                    }
                }
                .pickerStyle(.segmented)
                caption("The other enabled countdown appears underneath in gray.")
            }
            Divider()
            toggleRow("Start sessions when available", isOn: $autoStartAvailableSessions)
            caption("Off by default. When enabled, Session Pinger starts a newly available session even if it falls outside your schedule.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Notifications")

            toggleRow("Ping failures", isOn: $notifyOnFailure)
            toggleRow("Claude services down", isOn: $notifyOnServiceOutage)
            toggleRow("Claude performing poorly", isOn: $notifyOnServiceDegraded)
            toggleRow("New session available", isOn: $notifySessionAvailable)
            toggleRow("Session started by app", isOn: $notifySessionStarted)

            thresholdPicker(
                title: "Session usage alerts",
                subtitle: "Notify when the 5-hour window reaches:",
                selection: $sessionThresholds
            )
            thresholdPicker(
                title: "Weekly usage alerts",
                subtitle: "Notify when the 7-day window reaches:",
                selection: $weeklyThresholds
            )

            Button("Send test notification") {
                appState.sendTestNotification()
            }
            .claudeGhostButton()
            if let status = appState.notificationTestStatus {
                caption(status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thresholdPicker(title: String, subtitle: String, selection: Binding<Set<Int>>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ClaudeTheme.textPrimary)
            caption(subtitle)
            HStack(spacing: 6) {
                ForEach(SettingsStore.availableThresholds, id: \.self) { threshold in
                    thresholdPill(threshold: threshold, selection: selection)
                }
            }
        }
    }

    private func thresholdPill(threshold: Int, selection: Binding<Set<Int>>) -> some View {
        let isOn = selection.wrappedValue.contains(threshold)
        return Button(action: {
            if isOn {
                selection.wrappedValue.remove(threshold)
            } else {
                selection.wrappedValue.insert(threshold)
            }
        }) {
            Text("\(threshold)%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(isOn ? ClaudeTheme.accent : Color.primary.opacity(0.08)))
                .foregroundColor(isOn ? .white : ClaudeTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Click to stop notifying at \(threshold)%" : "Click to notify at \(threshold)%")
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "App")
            toggleRow("Launch at login", isOn: $launchAtLogin)
            toggleRow("Command-U opens menu", isOn: $enableCommandUShortcut)
            toggleRow("Use clear Liquid Glass", isOn: $preferClearGlass)
            caption("System Liquid Glass automatically follows appearance, contrast, motion, and transparency preferences.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: "Updates")
            toggleRow("Install updates automatically", isOn: $autoUpdate)
            caption("Current version: \(currentVersion)")
            if let update = appState.availableUpdate {
                Text("Version \(update.version) is available.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTheme.accent)
                if let installError = appState.installUpdateError {
                    Text(installError)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(appState.isInstallingUpdate ? "Installing\u{2026}" : "Install & Restart") {
                    appState.installUpdate()
                }
                .claudePrimaryButton()
                .disabled(appState.isInstallingUpdate)
            } else if let error = appState.updateCheckError {
                caption(error)
            } else {
                caption("You're on the latest version.")
            }
            Button(appState.isCheckingForUpdates ? "Checking\u{2026}" : "Check for updates") {
                Task { await appState.checkForUpdates() }
            }
            .claudeGhostButton()
            .disabled(appState.isCheckingForUpdates || appState.isInstallingUpdate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let testResult = testResult {
                Text(testResult)
                    .font(.system(size: 11))
                    .foregroundColor(testResult.hasPrefix("Success") ? ClaudeTheme.accent : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(isTesting ? "Testing\u{2026}" : "Test connection") {
                    runTest()
                }
                .claudeGhostButton()
                .disabled(isTesting)
                Spacer()
                Button("Cancel") {
                    appState.closeSettingsWindow?()
                }
                .claudeGhostButton()
                Button("Save") { save() }
                    .claudePrimaryButton()
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    private func formattedTimeNumbers(hour: Int, minute: Int) -> String {
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", displayHour, minute)
    }

    private func timePeriod(hour: Int) -> String {
        hour < 12 ? "AM" : "PM"
    }

    /// Login finished: store the session and the full cookie header, then
    /// make sure the organization ID is captured too -- from the cookie when
    /// available, otherwise fetched straight from claude.ai -- and refresh
    /// usage right away so the popover fills in without waiting for the next
    /// timer tick.
    private func handleLoginCapture(sessionKey: String, organizationIDFromCookie: String?, cookieHeader: String) {
        settings.sessionKey = sessionKey
        settings.cookieHeader = cookieHeader
        sessionKeyInput = ""
        loginCaptured = true
        testResult = nil
        if let organizationIDFromCookie, !organizationIDFromCookie.isEmpty {
            organizationID = organizationIDFromCookie
            settings.organizationID = organizationIDFromCookie
            Task { await appState.refreshUsage() }
            return
        }
        isFetchingOrganization = true
        Task {
            let fetched = await UsageChecker.fetchOrganizationID(sessionKey: sessionKey, cookieHeader: cookieHeader)
            await MainActor.run {
                isFetchingOrganization = false
                if let fetched, !fetched.isEmpty {
                    organizationID = fetched
                    settings.organizationID = fetched
                }
            }
            await appState.refreshUsage()
        }
    }

    private func loadCurrentValues() {
        organizationID = settings.organizationID
        model = settings.model
        message = settings.message
        slots = settings.scheduleSlots
        launchAtLogin = settings.launchAtLogin
        notifyOnFailure = settings.notifyOnFailure
        notifyOnServiceOutage = settings.notifyOnServiceOutage
        notifyOnServiceDegraded = settings.notifyOnServiceDegraded
        sessionThresholds = Set(settings.sessionUsageThresholds)
        weeklyThresholds = Set(settings.weeklyUsageThresholds)
        showSessionBar = settings.showSessionBar
        showWeeklyBar = settings.showWeeklyBar
        showFable5Bar = settings.showFable5Bar
        showNextPossibleCountdown = settings.showNextPossibleCountdown
        showScheduledCountdown = settings.showScheduledCountdown
        countdownFocus = settings.countdownFocus
        notifySessionAvailable = settings.notifySessionAvailable
        notifySessionStarted = settings.notifySessionStarted
        autoStartAvailableSessions = settings.autoStartAvailableSessions
        enableCommandUShortcut = settings.enableCommandUShortcut
        preferClearGlass = settings.preferClearGlass
        autoUpdate = settings.autoUpdateEnabled
        sessionKeyInput = ""
        testResult = nil
    }

    private func save(showPopoverAfterClose: Bool = false) {
        let trimmedSessionKeyInput = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSessionKeyInput.isEmpty {
            settings.sessionKey = trimmedSessionKeyInput
        }
        settings.organizationID = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.model = trimmedModel.isEmpty ? UsageChecker.fallbackModels[0] : trimmedModel
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.message = trimmedMessage.isEmpty ? "Say 1" : trimmedMessage
        settings.scheduleSlots = slots.isEmpty ? SettingsStore.defaultSlots : slots
        settings.launchAtLogin = launchAtLogin
        settings.notifyOnFailure = notifyOnFailure
        settings.notifyOnServiceOutage = notifyOnServiceOutage
        settings.notifyOnServiceDegraded = notifyOnServiceDegraded
        settings.sessionUsageThresholds = sessionThresholds.sorted()
        settings.weeklyUsageThresholds = weeklyThresholds.sorted()
        settings.showSessionBar = showSessionBar
        settings.showWeeklyBar = showWeeklyBar
        settings.showFable5Bar = showFable5Bar
        settings.showNextPossibleCountdown = showNextPossibleCountdown
        settings.showScheduledCountdown = showScheduledCountdown
        settings.countdownFocus = countdownFocus
        settings.notifySessionAvailable = notifySessionAvailable
        settings.notifySessionStarted = notifySessionStarted
        settings.autoStartAvailableSessions = autoStartAvailableSessions
        settings.enableCommandUShortcut = enableCommandUShortcut
        settings.preferClearGlass = preferClearGlass
        settings.autoUpdateEnabled = autoUpdate
        LoginItemManager.setEnabled(launchAtLogin)
        appState.rescheduleTimer()
        appState.closeSettingsWindow?()
        if showPopoverAfterClose {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                appState.requestTogglePopover?()
            }
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        let trimmedInput = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyToTest = trimmedInput.isEmpty ? settings.sessionKey : trimmedInput
        let orgToTest = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelToTest = selectedModel.isEmpty ? UsageChecker.fallbackModels[0] : selectedModel
        let messageToTest = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Say 1" : message
        // A manually pasted key can't be paired with the stored cookies (they
        // belong to the previous session), so fall back to just that key.
        let cookieHeaderToTest = trimmedInput.isEmpty ? settings.effectiveCookieHeader : "sessionKey=\(keyToTest)"
        Task {
            do {
                let outcome = try await ClaudeClient.sendPing(
                    sessionKey: keyToTest,
                    organizationID: orgToTest,
                    model: modelToTest,
                    message: messageToTest,
                    conversationID: settings.conversationID,
                    cookieHeader: cookieHeaderToTest
                )
                await MainActor.run {
                    settings.conversationID = outcome.conversationID
                    testResult = outcome.matchedExpected ? "Success: got expected reply" : "Connected, but reply was: \(outcome.replyText)"
                    isTesting = false
                }
            } catch {
                let description = (error as? PingError)?.localizedDescription ?? error.localizedDescription
                await MainActor.run {
                    testResult = description
                    isTesting = false
                }
            }
        }
    }
}
