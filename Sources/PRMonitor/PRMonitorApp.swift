import SwiftUI

@main
struct PRMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(count: appState.needsReviewCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.pull")
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
            }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PRSection(
                title: "Needs your review",
                prs: appState.needsReview,
                isExpanded: appState.bindingForSection("needsReview")
            )

            PRSection(
                title: "Waiting for reviewers",
                prs: appState.waitingForReviewers,
                isExpanded: appState.bindingForSection("waitingForReviewers")
            )

            PRSection(
                title: "Approved",
                prs: appState.approved,
                isExpanded: appState.bindingForSection("approved")
            )

            PRSection(
                title: "Reviewed",
                prs: appState.myChangesRequested,
                isExpanded: appState.bindingForSection("myChangesRequested")
            )

            Divider()
                .padding(.vertical, 4)

            if let error = appState.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            MenuRow(label: "Refresh", isLoading: appState.isLoading) {
                Task { await appState.refresh() }
            }

            MenuRow(label: "Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            MenuRow(label: "Open Full Version...") {
                NSWorkspace.shared.open(URL(string: "https://pr-monitor-zeta.vercel.app/")!)
            }

            MenuRow(label: "Quit") {
                NSApplication.shared.terminate(nil)
            }

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 380)
    }
}

struct MenuRow: View {
    let label: String
    var shortcut: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    MenuContent()
        .environmentObject(AppState.preview)
}
