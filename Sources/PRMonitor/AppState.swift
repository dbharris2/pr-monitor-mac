import SwiftUI
import Combine

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

    private let gitHubService = GitHubService()
    private var pollTimer: Timer?

    var needsReviewCount: Int {
        needsReview.count
    }

    init() {
        startPolling()
        Task {
            await refresh()
        }
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let results = try await gitHubService.fetchAllPRs()

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
