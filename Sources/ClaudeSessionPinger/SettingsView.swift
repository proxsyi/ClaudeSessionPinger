import SwiftUI

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
    @State private var autoUpdate = true
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showingLogin = false
    @State private var loginCaptured = false
    @State private var isFetchingOrganization = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ClaudeTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            // Content extends under the title bar (fullSizeContentView), so
            // push the header below the traffic-light buttons.
            .padding(.top, 38)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                // The glass container must live INSIDE the scroll view.
                // Glass effects render in their own layer keyed to the
                // container, so a container spanning the whole window let
                // panels draw outside the scrolling region (clipping through
                // the header and footer). Scoped to the scroll content, they
                // scroll and clip like normal views.
                VStack(alignment: .leading, spacing: 16) {
                    accountSection
                        .padding(14)
                        .glassPanel()
                    pingSection
                        .padding(14)
                        .glassPanel()
                    activitySection
                        .padding(14)
                        .glassPanel()
                    notificationsSection
                        .padding(14)
                        .glassPanel()
                    appSection
                        .padding(14)
                        .glassPanel()
                    updatesSection
                        .padding(14)
                        .glassPanel()
                }
                .claudeGlassContainer()
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .clipped()

            Divider()

            footer
                .background(.bar)
        }
        .frame(width: 420, height: 660)
        .background(WindowGlassBackground().ignoresSafeArea())
        .onAppear(perform: loadCurrentValues)
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
                            HStack(spacing: 12) {
                                Text(formattedTimeNumbers(hour: slots[index].hour, minute: slots[index].minute))
                                    .frame(width: 48, alignment: .leading)
                                Text(timePeriod(hour: slots[index].hour))
                                    .frame(width: 24, alignment: .leading)
                            }
                            .font(.system(size: 12).monospacedDigit())
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

            Button(appState.status == .sending ? "Sending\u{2026}" : "Ping now") {
                appState.pingNow()
            }
            .claudePrimaryButton()
            .disabled(appState.status == .sending)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var successRateText: String {
        guard stats.totalCount > 0 else { return "No pings yet" }
        return "\(stats.successCount)/\(stats.totalCount) (\(Int(stats.successRate * 100))%)"
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Notifications")

            toggleRow("Ping failures", isOn: $notifyOnFailure)
            toggleRow("Claude services down", isOn: $notifyOnServiceOutage)
            toggleRow("Claude performing poorly", isOn: $notifyOnServiceDegraded)

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
        autoUpdate = settings.autoUpdateEnabled
        sessionKeyInput = ""
        testResult = nil
    }

    private func save() {
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
        settings.autoUpdateEnabled = autoUpdate
        LoginItemManager.setEnabled(launchAtLogin)
        appState.rescheduleTimer()
        appState.closeSettingsWindow?()
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
                    cookieHeader: cookieHeaderToTest
                )
                await MainActor.run {
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
