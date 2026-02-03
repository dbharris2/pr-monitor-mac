import SwiftUI
import Combine
import UserNotifications

@MainActor
class AppState: ObservableObject {
    @Published var needsReview: [PullRequest] = []
    @Published var waitingForReviewers: [PullRequest] = []
    @Published var approved: [PullRequest] = []
    @Published var changesRequested: [PullRequest] = []
    @Published var myChangesRequested: [PullRequest] = []

    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var error: String?

    @Published var expandedSections: [String: Bool] = [
        "needsReview": true,
        "waitingForReviewers": true,
        "approved": false,
        "changesRequested": true,
        "myChangesRequested": true
    ]

    func bindingForSection(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.expandedSections[key] ?? true },
            set: { self.expandedSections[key] = $0 }
        )
    }

    @AppStorage("pollInterval") var pollInterval: TimeInterval = 300 // 5 minutes
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false

    private let gitHubService = GitHubService()
    private var pollTimer: Timer?
    private var notifiedPRIds: Set<String> = []
    private var previousApprovedIds: Set<String> = []
    private var previousChangesRequestedIds: Set<String> = []
    private var isFirstLoad = true

    var needsReviewCount: Int {
        needsReview.count
    }

    init() {
        startPolling()
        observeWake()
        Task {
            await refresh()
        }
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    #if DEBUG
    func resetNotificationTracking() {
        notifiedPRIds.removeAll()
        previousApprovedIds.removeAll()
        previousChangesRequestedIds.removeAll()
        isFirstLoad = false
    }

    func sendTestReviewRequestedNotification() {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let content = UNMutableNotificationContent()
            content.title = "Needs my review"
            content.subtitle = "acme/widgets #1234"
            content.body = "feat: Add dark mode support for dashboard"
            content.sound = .default

            if let attachment = Self.createReviewRequestedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    func sendTestApprovedNotification() {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let content = UNMutableNotificationContent()
            content.title = "Approved"
            content.subtitle = "acme/widgets #1234"
            content.body = "feat: Add dark mode support for dashboard"
            content.sound = .default

            if let attachment = Self.createApprovedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    func sendTestChangesRequestedNotification() {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let content = UNMutableNotificationContent()
            content.title = "Returned to me"
            content.subtitle = "acme/widgets #1234"
            content.body = "feat: Add dark mode support for dashboard"
            content.sound = .default

            if let attachment = Self.createChangesRequestedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
    #endif

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let results = try await gitHubService.fetchAllPRs()

            // Check for new PRs needing review (skip on first load)
            if !isFirstLoad && notificationsEnabled {
                let newPRs = results.needsReview.filter { !notifiedPRIds.contains($0.id) }
                if newPRs.count == 1 {
                    sendReviewRequestedNotification(for: newPRs[0])
                } else if newPRs.count > 1 {
                    sendSummaryNotification(count: newPRs.count)
                }

                // Check for newly approved PRs
                let newlyApproved = results.approved.filter { !previousApprovedIds.contains($0.id) }
                for pr in newlyApproved {
                    sendApprovedNotification(for: pr)
                }

                // Check for PRs with newly requested changes
                let newlyChangesRequested = results.changesRequested.filter { !previousChangesRequestedIds.contains($0.id) }
                for pr in newlyChangesRequested {
                    sendChangesRequestedNotification(for: pr)
                }
            }

            // Track all current PR IDs
            notifiedPRIds = Set(results.needsReview.map { $0.id })
            previousApprovedIds = Set(results.approved.map { $0.id })
            previousChangesRequestedIds = Set(results.changesRequested.map { $0.id })
            isFirstLoad = false

            needsReview = results.needsReview
            waitingForReviewers = results.waitingForReviewers
            approved = results.approved
            changesRequested = results.changesRequested
            myChangesRequested = results.myChangesRequested

            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func sendReviewRequestedNotification(for pr: PullRequest) {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let content = UNMutableNotificationContent()
            content.title = "Needs my review"
            content.body = pr.title
            content.subtitle = "\(pr.repository) #\(pr.number)"
            content.sound = .default
            content.userInfo = ["url": pr.url.absoluteString]

            if let attachment = Self.createReviewRequestedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func createReviewRequestedIconAttachment() -> UNNotificationAttachment? {
        guard let image = NSImage(named: "ReviewRequestedIcon"),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("review-icon.png")
        do {
            try pngData.write(to: tempURL)
            return try UNNotificationAttachment(identifier: "review-icon", url: tempURL, options: nil)
        } catch {
            return nil
        }
    }

    private func sendApprovedNotification(for pr: PullRequest) {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let content = UNMutableNotificationContent()
            content.title = "Approved"
            content.body = pr.title
            content.subtitle = "\(pr.repository) #\(pr.number)"
            content.sound = .default
            content.userInfo = ["url": pr.url.absoluteString]

            if let attachment = Self.createApprovedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func createApprovedIconAttachment() -> UNNotificationAttachment? {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: rect).fill()

            if let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .bold)
                let tinted = checkmark.withSymbolConfiguration(config)
                NSColor.white.set()
                let checkSize = NSSize(width: 32, height: 32)
                let checkRect = NSRect(
                    x: (rect.width - checkSize.width) / 2,
                    y: (rect.height - checkSize.height) / 2,
                    width: checkSize.width,
                    height: checkSize.height
                )
                tinted?.draw(in: checkRect, from: .zero, operation: .destinationOver, fraction: 1.0)

                // Draw checkmark in white
                if let cgImage = tinted?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let ctx = NSGraphicsContext.current?.cgContext
                    ctx?.saveGState()
                    ctx?.clip(to: checkRect, mask: cgImage)
                    ctx?.setFillColor(NSColor.white.cgColor)
                    ctx?.fill(checkRect)
                    ctx?.restoreGState()
                }
            }
            return true
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("approved-icon.png")
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: tempURL)
            return try UNNotificationAttachment(identifier: "approved-icon", url: tempURL, options: nil)
        } catch {
            return nil
        }
    }

    private func sendChangesRequestedNotification(for pr: PullRequest) {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let content = UNMutableNotificationContent()
            content.title = "Returned to me"
            content.body = pr.title
            content.subtitle = "\(pr.repository) #\(pr.number)"
            content.sound = .default
            content.userInfo = ["url": pr.url.absoluteString]

            if let attachment = Self.createChangesRequestedIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func createChangesRequestedIconAttachment() -> UNNotificationAttachment? {
        guard let image = NSImage(named: "ChangesRequestedIcon"),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("changes-icon.png")
        do {
            try pngData.write(to: tempURL)
            return try UNNotificationAttachment(identifier: "changes-icon", url: tempURL, options: nil)
        } catch {
            return nil
        }
    }

    private func sendSummaryNotification(count: Int) {
        NSApp.deactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let content = UNMutableNotificationContent()
            content.title = "Need my review"
            content.body = "\(count) PRs need your review"
            content.sound = .default
            content.userInfo = ["url": "https://pr-monitor-zeta.vercel.app/"]

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    static var preview: AppState {
        let state = AppState()
        state.needsReview = [
            PullRequest(
                id: "1",
                number: 42,
                title: "feat: Add dark mode support",
                url: URL(string: "https://github.com/owner/repo/pull/42")!,
                repository: "owner/repo",
                author: "alice",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4"),
                createdAt: Date().addingTimeInterval(-86400),
                isDraft: false,
                reviewDecision: nil
            ),
            PullRequest(
                id: "2",
                number: 123,
                title: "fix: Resolve memory leak in image loader",
                url: URL(string: "https://github.com/owner/other/pull/123")!,
                repository: "owner/other",
                author: "bob",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4"),
                createdAt: Date().addingTimeInterval(-3600),
                isDraft: false,
                reviewDecision: nil
            )
        ]
        state.waitingForReviewers = [
            PullRequest(
                id: "3",
                number: 31,
                title: "feat: Both panel compact mode",
                url: URL(string: "https://github.com/owner/repo/pull/31")!,
                repository: "owner/repo",
                author: "me",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/3?v=4"),
                createdAt: Date().addingTimeInterval(-7200),
                isDraft: false,
                reviewDecision: nil
            )
        ]
        state.lastUpdated = Date()
        return state
    }
}
