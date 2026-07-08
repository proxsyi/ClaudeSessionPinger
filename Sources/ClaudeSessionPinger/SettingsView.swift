import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState

    @State private var sessionKeyInput = ""
    @State private var organizationID = ""
    @State private var model = ""
    @State private var message = ""
    @State private var slots: [ScheduleSlot] = []
    @State private var launchAtLogin = false
    @State private var notifyOnFailure = true
    @State private var notifyOnServiceOutage = true
    @State private var sessionThresholds: Set<Int> = []
    @State private var weeklyThresholds: Set<Int> = []
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showingLogin = false
    @State private var loginCaptured = false
    @State private var isFetchingOrganization = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SETTINGS")
                        .font(ClaudeTheme.pixelFont(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundColor(ClaudeTheme.textPrimary)

                    accountSection
                        .padding(12)
                        .glassPanel()
                    pingSection
                        .padding(12)
                        .glassPanel(tint: ClaudeTheme.accent)
                    notificationsSection
                        .padding(12)
                        .glassPanel()
                    appSection
                        .padding(12)
                        .glassPanel()
                    updatesSection
                        .padding(12)
                        .glassPanel()
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .claudeGlassContainer()
        .frame(width: 400, height: 640)
        .background(.regularMaterial)
        .onAppear(perform: loadCurrentValues)
        .sheet(isPresented: $showingLogin) {
            CookieLoginSheet { sessionKey, organizationIDFromCookie in
                handleLoginCapture(sessionKey: sessionKey, organizationIDFromCookie: organizationIDFromCookie)
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelSectionHeader(text: "Account")

            Button(loginCaptured || !settings.sessionKey.isEmpty ? "Log in again" : "Log in with Claude") {
                showingLogin = true
            }
            .claudePrimaryButton()

            if loginCaptured {
                Text("Signed in -- session captured automatically.")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.accent)
            } else if !settings.sessionKey.isEmpty {
                Text("Using a previously captured session (\(settings.maskedSessionKey)).")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
            }

            if isFetchingOrganization {
                Text("Detecting your organization ID\u{2026}")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
            } else if loginCaptured && organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Couldn't detect your organization ID automatically. Open claude.ai in a browser, open Dev Tools \u{2192} Application \u{2192} Cookies, and paste the value of \"lastActiveOrg\" below.")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Organization ID")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
                TextField("Filled automatically on login", text: $organizationID)
                    .textFieldStyle(.roundedBorder)
            }

            DisclosureGroup("Advanced: paste session key manually") {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField(settings.sessionKey.isEmpty ? "Paste sessionKey cookie" : settings.maskedSessionKey, text: $sessionKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Text("Only needed if the built-in login doesn't work for your account.")
                        .font(ClaudeTheme.pixelFont(size: 9))
                        .foregroundColor(ClaudeTheme.textSecondary)
                }
                .padding(.top, 4)
            }
            .font(ClaudeTheme.pixelFont(size: 10))
            .foregroundColor(ClaudeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelSectionHeader(text: "Ping")

            VStack(alignment: .leading, spacing: 4) {
                Text("Model slug")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
                TextField("claude-haiku-4-5-...", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
                TextField("Say 1", text: $message)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Schedule")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
                ForEach(slots.indices, id: \.self) { index in
                    HStack {
                        Stepper(value: Binding(
                            get: { slots[index].hour },
                            set: { slots[index].hour = $0 }
                        ), in: 0...23) {
                            Text(formattedTime(hour: slots[index].hour, minute: slots[index].minute))
                                .font(ClaudeTheme.pixelFont(size: 12))
                                .foregroundColor(ClaudeTheme.textPrimary)
                                .frame(width: 84, alignment: .leading)
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
                .font(ClaudeTheme.pixelFont(size: 11, weight: .semibold))
                .foregroundColor(ClaudeTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelSectionHeader(text: "Notifications")

            Toggle("Notify on ping failure", isOn: $notifyOnFailure)
                .font(ClaudeTheme.pixelFont(size: 11))
            Toggle("Notify on Claude service outages", isOn: $notifyOnServiceOutage)
                .font(ClaudeTheme.pixelFont(size: 11))

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thresholdPicker(title: String, subtitle: String, selection: Binding<Set<Int>>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ClaudeTheme.pixelFont(size: 11, weight: .semibold))
                .foregroundColor(ClaudeTheme.textPrimary)
            Text(subtitle)
                .font(ClaudeTheme.pixelFont(size: 9))
                .foregroundColor(ClaudeTheme.textSecondary)
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
                .font(ClaudeTheme.pixelFont(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Rectangle().fill(isOn ? ClaudeTheme.accent : Color.primary.opacity(0.08)))
                .foregroundColor(isOn ? .white : ClaudeTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Click to stop notifying at \(threshold)%" : "Click to notify at \(threshold)%")
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelSectionHeader(text: "App")
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(ClaudeTheme.pixelFont(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PixelSectionHeader(text: "Updates")
            Text("Current version: \(currentVersion)")
                .font(ClaudeTheme.pixelFont(size: 10))
                .foregroundColor(ClaudeTheme.textSecondary)
            if let update = appState.availableUpdate {
                Text("Version \(update.version) is available.")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.accent)
                if let installError = appState.installUpdateError {
                    Text(installError)
                        .font(ClaudeTheme.pixelFont(size: 9))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(appState.isInstallingUpdate ? "Installing\u{2026}" : "Install & Restart") {
                    appState.installUpdate()
                }
                .claudePrimaryButton()
                .disabled(appState.isInstallingUpdate)
            } else if let error = appState.updateCheckError {
                Text(error)
                    .font(ClaudeTheme.pixelFont(size: 9))
                    .foregroundColor(ClaudeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You're on the latest version.")
                    .font(ClaudeTheme.pixelFont(size: 10))
                    .foregroundColor(ClaudeTheme.textSecondary)
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
                    .font(ClaudeTheme.pixelFont(size: 10))
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

    /// Formats a 24-hour `hour`/`minute` pair as a fixed 12-hour clock string
    /// (e.g. "5:00 AM", "3:00 PM"), regardless of the system's clock format
    /// setting, since the schedule is easier to scan that way.
    private func formattedTime(hour: Int, minute: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    /// Login finished: store the session, then make sure the organization ID
    /// is captured too -- from the cookie when available, otherwise fetched
    /// straight from claude.ai -- and refresh usage right away so the popover
    /// fills in without waiting for the next timer tick.
    private func handleLoginCapture(sessionKey: String, organizationIDFromCookie: String?) {
        settings.sessionKey = sessionKey
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
            let fetched = await UsageChecker.fetchOrganizationID(sessionKey: sessionKey)
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
        sessionThresholds = Set(settings.sessionUsageThresholds)
        weeklyThresholds = Set(settings.weeklyUsageThresholds)
        sessionKeyInput = ""
        testResult = nil
    }

    private func save() {
        let trimmedSessionKeyInput = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSessionKeyInput.isEmpty {
            settings.sessionKey = trimmedSessionKeyInput
        }
        settings.organizationID = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.message = trimmedMessage.isEmpty ? "Say 1" : trimmedMessage
        settings.scheduleSlots = slots.isEmpty ? SettingsStore.defaultSlots : slots
        settings.launchAtLogin = launchAtLogin
        settings.notifyOnFailure = notifyOnFailure
        settings.notifyOnServiceOutage = notifyOnServiceOutage
        settings.sessionUsageThresholds = sessionThresholds.sorted()
        settings.weeklyUsageThresholds = weeklyThresholds.sorted()
        LoginItemManager.setEnabled(launchAtLogin)
        appState.rescheduleTimer()
        appState.closeSettingsWindow?()
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        let keyToTest = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? settings.sessionKey : sessionKeyInput
        let orgToTest = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelToTest = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageToTest = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Say 1" : message
        Task {
            do {
                let outcome = try await ClaudeClient.sendPing(
                    sessionKey: keyToTest,
                    organizationID: orgToTest,
                    model: modelToTest,
                    message: messageToTest
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
