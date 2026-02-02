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
    private var isFirstLoad = true

    var needsReviewCount: Int {
        needsReview.count
    }

    init() {
        startPolling()
        Task {
            await refresh()
        }
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let results = try await gitHubService.fetchAllPRs()

            // Check for new PRs needing review (skip on first load)
            if !isFirstLoad && notificationsEnabled {
                for pr in results.needsReview {
                    if !notifiedPRIds.contains(pr.id) {
                        sendNotification(for: pr)
                    }
                }
            }

            // Track all current needsReview PR IDs
            notifiedPRIds = Set(results.needsReview.map { $0.id })
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

    private func sendNotification(for pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "Review Requested"
        content.body = "#\(pr.number): \(pr.title)"
        content.subtitle = pr.repository
        content.sound = .default
        content.userInfo = ["url": pr.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: pr.id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
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
                createdAt: Date().addingTimeInterval(-7200),
                isDraft: false,
                reviewDecision: nil
            )
        ]
        state.lastUpdated = Date()
        return state
    }
}
