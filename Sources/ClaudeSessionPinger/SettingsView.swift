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
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showingLogin = false
    @State private var loginCaptured = false

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ClaudeTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Account").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    Button(loginCaptured || !settings.sessionKey.isEmpty ? "Log in again" : "Log in with Claude") {
                        showingLogin = true
                    }
                    .claudePrimaryButton()
                    if loginCaptured {
                        Text("Signed in -- session captured automatically.")
                            .font(.system(size: 11))
                            .foregroundColor(ClaudeTheme.accent)
                        if organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Couldn't detect your organization ID automatically. Open claude.ai in a browser, open Dev Tools \u{2192} Application \u{2192} Cookies, and paste the value of \"lastActiveOrg\" into the field below.")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if !settings.sessionKey.isEmpty {
                        Text("Using a previously captured session (\(settings.maskedSessionKey)).")
                            .font(.system(size: 11))
                            .foregroundColor(ClaudeTheme.textSecondary)
                    }
                }

                DisclosureGroup("Advanced: paste session key manually") {
                    VStack(alignment: .leading, spacing: 4) {
                        SecureField(settings.sessionKey.isEmpty ? "Paste sessionKey cookie" : settings.maskedSessionKey, text: $sessionKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Text("Only needed if the built-in login doesn't work for your account.")
                            .font(.system(size: 10))
                            .foregroundColor(ClaudeTheme.textSecondary)
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11))
                .foregroundColor(ClaudeTheme.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization ID").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    TextField("Organization UUID", text: $organizationID)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model slug").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    TextField("claude-haiku-4-5-...", text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Message").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    TextField("Say 1", text: $message)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Schedule").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    ForEach(slots.indices, id: \.self) { index in
                        HStack {
                            Stepper(value: Binding(
                                get: { slots[index].hour },
                                set: { slots[index].hour = $0 }
                            ), in: 0...23) {
                                Text(formattedTime(hour: slots[index].hour, minute: slots[index].minute))
                                    .foregroundColor(ClaudeTheme.textPrimary)
                                    .monospacedDigit()
                                    .frame(width: 72, alignment: .leading)
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
                    .foregroundColor(ClaudeTheme.accent)
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Notify on failure", isOn: $notifyOnFailure)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Updates").font(.system(size: 11)).foregroundColor(ClaudeTheme.textSecondary)
                    Text("Current version: \(currentVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(ClaudeTheme.textSecondary)
                    if let update = appState.availableUpdate {
                        Text("Version \(update.version) is available.")
                            .font(.system(size: 11))
                            .foregroundColor(ClaudeTheme.accent)
                        if let installError = appState.installUpdateError {
                            Text(installError)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(appState.isInstallingUpdate ? "Installing…" : "Install & Restart") {
                            appState.installUpdate()
                        }
                        .claudePrimaryButton()
                        .disabled(appState.isInstallingUpdate)
                    } else if let error = appState.updateCheckError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(ClaudeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("You're on the latest version.")
                            .font(.system(size: 11))
                            .foregroundColor(ClaudeTheme.textSecondary)
                    }
                    Button(appState.isCheckingForUpdates ? "Checking…" : "Check for updates") {
                        Task { await appState.checkForUpdates() }
                    }
                    .claudeGhostButton()
                    .disabled(appState.isCheckingForUpdates || appState.isInstallingUpdate)
                }
            }
            .padding(20)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            if let testResult = testResult {
                Text(testResult)
                    .font(.system(size: 11))
                    .foregroundColor(testResult.hasPrefix("Success") ? ClaudeTheme.accent : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(isTesting ? "Testing…" : "Test connection") {
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
        .claudeGlassContainer()
        .frame(width: 380, height: 560)
        .background(.regularMaterial)
        .onAppear(perform: loadCurrentValues)
        .sheet(isPresented: $showingLogin) {
            CookieLoginSheet { sessionKey, organizationIDFromCookie in
                settings.sessionKey = sessionKey
                sessionKeyInput = ""
                if let organizationIDFromCookie, !organizationIDFromCookie.isEmpty {
                    organizationID = organizationIDFromCookie
                }
                loginCaptured = true
                testResult = nil
            }
        }
    }

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

    private func loadCurrentValues() {
        organizationID = settings.organizationID
        model = settings.model
        message = settings.message
        slots = settings.scheduleSlots
        launchAtLogin = settings.launchAtLogin
        notifyOnFailure = settings.notifyOnFailure
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
