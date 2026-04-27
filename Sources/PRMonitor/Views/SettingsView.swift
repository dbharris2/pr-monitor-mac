import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    @State private var showSignOutInstructions = false

    private let pollIntervalOptions: [(String, TimeInterval)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
    ]

    var body: some View {
        Form {
            Section {
                ghAuthSection
            } header: {
                Text("GitHub Authentication")
            }

            Section {
                Picker("Poll interval", selection: $appState.pollInterval) {
                    ForEach(pollIntervalOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                .onChange(of: appState.pollInterval) { _, _ in
                    appState.startPolling()
                }
            } header: {
                Text("Refresh")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Toggle("Notifications", isOn: $appState.notificationsEnabled)
                    .onChange(of: appState.notificationsEnabled) { _, newValue in
                        if newValue {
                            appState.requestNotificationPermissions()
                        }
                    }

                Picker("Menu bar indicator", selection: $appState.menuBarStyle) {
                    Text("Dots (compact)").tag("dots")
                    Text("Colored numbers").tag("numbers")
                }

                KeyboardShortcuts.Recorder("Global shortcut:", name: .toggleMenuBar)
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
        .task { await appState.refreshAuthStatus() }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Sign out of GitHub CLI", isPresented: $showSignOutInstructions) {
            Button("Copy command") { copy("gh auth logout") }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Run `gh auth logout` in your terminal to sign out. PR Monitor will detect the change on the next refresh.")
        }
    }

    @ViewBuilder
    private var ghAuthSection: some View {
        switch appState.ghAuthStatus {
        case .unknown:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub CLI…").foregroundStyle(.secondary)
            }
        case .ghMissing:
            authStateCard(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "GitHub CLI not found",
                instruction: "Install with:",
                command: "brew install gh"
            )
        case .notAuthenticated:
            authStateCard(
                systemImage: "person.slash",
                tint: .orange,
                title: "Not signed in",
                instruction: "Run this in your terminal:",
                command: "gh auth login"
            )
        case let .authenticated(login):
            HStack {
                Label {
                    Text("Signed in as @\(login) via gh CLI")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Sign out") { showSignOutInstructions = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func authStateCard(systemImage: String, tint: Color, title: String, instruction: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button("Copy") { copy(command) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Spacer()
                Button("Re-check") {
                    Task {
                        await appState.refreshAuthStatus()
                        await appState.refresh()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail - user can retry via the toggle
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.preview)
}
