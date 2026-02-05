import MenuBarExtraAccess
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Keychain.migrateFromUserDefaultsIfNeeded()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
            MenuBarLabel(
                approvedCount: appState.approved.count,
                needsReviewCount: appState.needsReviewCount,
                changesRequestedCount: appState.changesRequested.count,
                style: appState.menuBarStyle
            )
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $appState.isMenuPresented)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct MenuBarLabel: View {
    let approvedCount: Int
    let needsReviewCount: Int
    let changesRequestedCount: Int
    let style: String

    var body: some View {
        Image(nsImage: createMenuBarImage())
    }

    private func createMenuBarImage() -> NSImage {
        let iconSize: CGFloat = 18
        let gapAfterIcon: CGFloat = 3
        let iconTint: NSColor = .white

        // Colors for each category
        let greenColor = NSColor.systemGreen
        let orangeColor = NSColor(red: 247 / 255, green: 129 / 255, blue: 102 / 255, alpha: 1)
        let redColor = NSColor.systemRed

        // Build items to display (color, count)
        var items: [(NSColor, Int)] = []
        if approvedCount > 0 { items.append((greenColor, approvedCount)) }
        if needsReviewCount > 0 { items.append((orangeColor, needsReviewCount)) }
        if changesRequestedCount > 0 { items.append((redColor, changesRequestedCount)) }

        if style == "numbers" {
            return createNumbersImage(iconSize: iconSize, gapAfterIcon: gapAfterIcon, iconTint: iconTint, items: items)
        } else {
            return createDotsImage(iconSize: iconSize, gapAfterIcon: gapAfterIcon, iconTint: iconTint, items: items)
        }
    }

    private func createDotsImage(iconSize: CGFloat, gapAfterIcon: CGFloat, iconTint: NSColor, items: [(NSColor, Int)]) -> NSImage {
        let dotSize: CGFloat = 5
        let dotSpacing: CGFloat = 1

        let dotsWidth = items.isEmpty ? 0 : dotSize
        let totalWidth = iconSize + (items.isEmpty ? 0 : gapAfterIcon + dotsWidth)
        let totalHeight = iconSize

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            drawIcon(iconSize: iconSize, iconTint: iconTint)

            if !items.isEmpty {
                let dotsX = iconSize + gapAfterIcon
                let totalDotsHeight = CGFloat(items.count) * dotSize + CGFloat(items.count - 1) * dotSpacing
                var currentY = (totalHeight - totalDotsHeight) / 2 + totalDotsHeight - dotSize

                for (color, _) in items {
                    color.setFill()
                    let dotRect = NSRect(x: dotsX, y: currentY, width: dotSize, height: dotSize)
                    NSBezierPath(ovalIn: dotRect).fill()
                    currentY -= (dotSize + dotSpacing)
                }
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func createNumbersImage(iconSize: CGFloat, gapAfterIcon: CGFloat, iconTint: NSColor, items: [(NSColor, Int)]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let numberSpacing: CGFloat = 3

        // Calculate width needed for numbers
        var numbersWidth: CGFloat = 0
        var attributedStrings: [(NSAttributedString, NSColor)] = []

        for (color, count) in items {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let displayText = count > 99 ? "99+" : "\(count)"
            let str = NSAttributedString(string: displayText, attributes: attrs)
            attributedStrings.append((str, color))
            numbersWidth += str.size().width
        }

        if !items.isEmpty {
            numbersWidth += CGFloat(items.count - 1) * numberSpacing
        }

        let totalWidth = iconSize + (items.isEmpty ? 0 : gapAfterIcon + numbersWidth)
        let totalHeight = iconSize

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            drawIcon(iconSize: iconSize, iconTint: iconTint)

            if !attributedStrings.isEmpty {
                var currentX = iconSize + gapAfterIcon

                for (str, _) in attributedStrings {
                    let size = str.size()
                    let y = (totalHeight - size.height) / 2
                    str.draw(at: NSPoint(x: currentX, y: y))
                    currentX += size.width + numberSpacing
                }
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func drawIcon(iconSize: CGFloat, iconTint: NSColor) {
        if let icon = NSImage(named: "MenuBarIcon") {
            let iconRect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)

            if let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ctx = NSGraphicsContext.current?.cgContext
                ctx?.saveGState()
                ctx?.clip(to: iconRect, mask: cgImage)
                ctx?.setFillColor(iconTint.cgColor)
                ctx?.fill(iconRect)
                ctx?.restoreGState()
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
                isExpanded: appState.bindingForSection("needsReview"),
                statusColorOverride: .gitHubOrange
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

                MenuRow(label: "Reset Notification Tracking") {
                    appState.resetNotificationTracking()
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
    var shortcut: String?
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
                        .foregroundColor(isHovered ? .white.opacity(0.8) : .gray)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isHovered ? .white : .primary)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
            )
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
                    .fill(isExpanded ? Color(nsColor: .selectedContentBackgroundColor) : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
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
