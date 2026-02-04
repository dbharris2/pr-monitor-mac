import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var token: String = ""
    @State private var showToken = false
    @State private var launchAtLogin = false

    private let pollIntervalOptions: [(String, TimeInterval)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    if showToken {
                        TextField("GitHub Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("GitHub Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("Save Token") {
                    Keychain.setToken(token)
                    Task {
                        await appState.refresh()
                    }
                }

                Text("Create a token at GitHub → Settings → Developer settings → Personal access tokens. Needs `repo` scope for private repos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 400, height: 360)
        .onAppear {
            if let existingToken = Keychain.getToken() {
                token = existingToken
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
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
