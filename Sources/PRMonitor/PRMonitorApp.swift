import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}

@main
struct PRMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
            Image("MenuBarIcon")
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
                title: "Needs my review",
                prs: appState.needsReview,
                isExpanded: appState.bindingForSection("needsReview")
            )

            PRSection(
                title: "Waiting for review",
                prs: appState.waitingForReviewers,
                isExpanded: appState.bindingForSection("waitingForReviewers")
            )

            PRSection(
                title: "Approved",
                prs: appState.approved,
                isExpanded: appState.bindingForSection("approved")
            )

            PRSection(
                title: "Returned to me",
                prs: appState.changesRequested,
                isExpanded: appState.bindingForSection("changesRequested")
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

            #if DEBUG
            SubMenuRow(label: "Test Notification") {
                MenuRow(label: "Needs my review") {
                    appState.sendTestReviewRequestedNotification()
                }
                MenuRow(label: "Approved") {
                    appState.sendTestApprovedNotification()
                }
                MenuRow(label: "Returned to me") {
                    appState.sendTestChangesRequestedNotification()
                }
            }
            #endif

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

struct SubMenuRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isExpanded ? Color.accentColor : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
            )
            .foregroundStyle(isExpanded ? .white : .primary)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.leading, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    MenuContent()
        .environmentObject(AppState.preview)
}
