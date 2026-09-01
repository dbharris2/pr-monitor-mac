import Combine
import KeyboardShortcuts
import SwiftUI
import UserNotifications

@MainActor
class AppState: ObservableObject {
    @Published var needsReview: [PullRequest] = []
    @Published var waitingForReviewers: [PullRequest] = []
    @Published var approved: [PullRequest] = []
    @Published var changesRequested: [PullRequest] = []
    @Published var myChangesRequested: [PullRequest] = []
    @Published var drafts: [PullRequest] = []

    @Published var snoozeManager = SnoozeManager()
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var isMenuPresented = false
    @Published var updateAvailable: String?
    @Published var ghAuthStatus: GHAuthStatus = .unknown
    @Published private(set) var customReviewFilters: [ReviewFilter] = []

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    @Published var expandedSections: [String: Bool] = [
        "filters": true,
        "needsReview": true,
        "waitingForReviewers": true,
        "approved": false,
        "changesRequested": true,
        "myChangesRequested": true,
        "drafts": false,
        "snoozed": false
    ]

    func bindingForSection(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.expandedSections[key] ?? true },
            set: { self.expandedSections[key] = $0 }
        )
    }

    @AppStorage("pollInterval") var pollInterval: TimeInterval = 300 // 5 minutes
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("menuBarStyle") var menuBarStyle: String = "numbers" // "dots" or "numbers"
    private let gitHubService: GitHubServiceProtocol
    private let gh: GHCommandProtocol
    private let userDefaults: UserDefaults
    private var pollTimer: Timer?
    private var snoozeCancellable: AnyCancellable?
    private var notifiedPRIds: Set<String> = []
    private var previousApprovedIds: Set<String> = []
    private var previousChangesRequestedIds: Set<String> = []
    private var isFirstLoad = true
    private var isCheckingAuth = false

    private var activeReviewFilterID: String {
        get { userDefaults.string(forKey: "activeReviewFilterID") ?? ReviewFilter.allID }
        set { userDefaults.set(newValue, forKey: "activeReviewFilterID") }
    }

    var reviewFiltersForMenu: [ReviewFilter] {
        [ReviewFilter.all] + customReviewFilters
    }

    var activeReviewFilter: ReviewFilter {
        reviewFiltersForMenu.first { $0.id == activeReviewFilterID } ?? .all
    }

    var visibleNeedsReview: [PullRequest] {
        filteredPRs(needsReview, filter: activeReviewFilter)
    }

    var visibleWaitingForReviewers: [PullRequest] {
        unsnoozedPRs(waitingForReviewers)
    }

    var visibleApproved: [PullRequest] {
        unsnoozedPRs(approved)
    }

    var visibleChangesRequested: [PullRequest] {
        unsnoozedPRs(changesRequested)
    }

    var visibleMyChangesRequested: [PullRequest] {
        filteredPRs(myChangesRequested, filter: activeReviewFilter)
    }

    var visibleDrafts: [PullRequest] {
        unsnoozedPRs(drafts)
    }

    var snoozedPRs: [PullRequest] {
        let snoozedIDs = snoozeManager.snoozedIDs
        let allPRs = needsReview + waitingForReviewers + approved + changesRequested + myChangesRequested + drafts
        return allPRs.filter { snoozedIDs.contains($0.id) }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var needsReviewCount: Int {
        visibleNeedsReview.count
    }

    func selectReviewFilter(_ filter: ReviewFilter) {
        objectWillChange.send()
        activeReviewFilterID = filter.id
        // Treat the currently visible PRs as already observed when changing filters.
        // This prevents selecting a filter from notifying about old PRs that were
        // already present under another filter.
        notifiedPRIds = Set(filteredPRs(needsReview, filter: filter).map(\.id))
    }

    func saveReviewFilter(_ filter: ReviewFilter) {
        if let index = customReviewFilters.firstIndex(where: { $0.id == filter.id }) {
            customReviewFilters[index] = filter
        } else {
            customReviewFilters.append(filter)
        }
        customReviewFilters.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistReviewFilters()
    }

    func deleteReviewFilter(_ filter: ReviewFilter) {
        customReviewFilters.removeAll { $0.id == filter.id }
        if activeReviewFilterID == filter.id {
            activeReviewFilterID = ReviewFilter.allID
        }
        persistReviewFilters()
    }

    func counts(for filter: ReviewFilter) -> ReviewFilterCounts {
        ReviewFilterCounts(
            needsReview: filteredPRs(needsReview, filter: filter).count,
            approved: unsnoozedPRs(approved).count,
            changesRequested: unsnoozedPRs(changesRequested).count
        )
    }

    init(
        service: GitHubServiceProtocol = GitHubService(),
        gh: GHCommandProtocol = GHCommand.shared,
        startAutomatically: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.gitHubService = service
        self.gh = gh
        self.userDefaults = userDefaults
        customReviewFilters = Self.loadReviewFilters(from: userDefaults)
        snoozeCancellable = snoozeManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        guard startAutomatically else { return }
        startPolling()
        observeWake()
        setupKeyboardShortcut()
        Task {
            await refreshAuthStatus()
            await refresh()
        }
    }

    func refreshAuthStatus() async {
        guard !isCheckingAuth else { return }
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        do {
            _ = try await gh.resolveBinary()
        } catch {
            ghAuthStatus = .ghMissing
            return
        }

        do {
            let stdout = try await gh.runExpectingSuccess(
                arguments: ["api", "user", "--jq", ".login"],
                stdin: nil,
                timeout: 15
            )
            let login = (String(data: stdout, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ghAuthStatus = login.isEmpty ? .notAuthenticated : .authenticated(login: login)
        } catch {
            ghAuthStatus = .notAuthenticated
        }
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleMenuBar) { [weak self] in
            Task { @MainActor in
                self?.isMenuPresented.toggle()
            }
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

    func refresh() async {
        guard !isLoading else { return }

        // Lets the user recover from "not signed in" by running `gh auth login` and clicking refresh.
        if !ghAuthStatus.isHealthy { await refreshAuthStatus() }
        if let authError = ghAuthStatus.errorDescription {
            error = authError
            return
        }

        isLoading = true
        error = nil
        snoozeManager.cleanExpired()

        do {
            let results = try await gitHubService.fetchAllPRs()

            // Check for new PRs needing review (skip on first load)
            if !isFirstLoad, notificationsEnabled {
                let snoozedIDs = snoozeManager.snoozedIDs
                let newPRs = results.needsReview.filter {
                    !notifiedPRIds.contains($0.id)
                        && !snoozedIDs.contains($0.id)
                        && matchesReviewFilter($0, filter: activeReviewFilter)
                }
                if newPRs.count == 1 {
                    sendReviewRequestedNotification(for: newPRs[0])
                } else if newPRs.count > 1 {
                    sendSummaryNotification(count: newPRs.count)
                }

                // Check for newly approved PRs
                let newlyApproved = results.approved.filter {
                    !previousApprovedIds.contains($0.id)
                        && !snoozedIDs.contains($0.id)
                }
                for pr in newlyApproved {
                    sendApprovedNotification(for: pr)
                }

                // Check for PRs with newly requested changes
                let newlyChangesRequested = results.changesRequested
                    .filter {
                        !previousChangesRequestedIds.contains($0.id)
                            && !snoozedIDs.contains($0.id)
                    }
                for pr in newlyChangesRequested {
                    sendChangesRequestedNotification(for: pr)
                }
            }

            // Track only current PRs matching the active filter.
            notifiedPRIds = Set(
                results.needsReview
                    .filter { matchesReviewFilter($0, filter: activeReviewFilter) }
                    .map(\.id)
            )
            previousApprovedIds = Set(results.approved.map(\.id))
            previousChangesRequestedIds = Set(results.changesRequested.map(\.id))
            isFirstLoad = false

            needsReview = results.needsReview
            waitingForReviewers = results.waitingForReviewers
            approved = results.approved
            changesRequested = results.changesRequested
            myChangesRequested = results.myChangesRequested
            drafts = results.drafts

            lastUpdated = Date()

            // Check for updates (don't let failures affect the main refresh)
            if let latest = try? await gitHubService.fetchLatestRelease() {
                updateAvailable = Self.isNewer(latest, than: appVersion) ? latest : nil
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func filteredPRs(_ prs: [PullRequest], filter: ReviewFilter) -> [PullRequest] {
        unsnoozedPRs(prs).filter { matchesReviewFilter($0, filter: filter) }
    }

    private func unsnoozedPRs(_ prs: [PullRequest]) -> [PullRequest] {
        let snoozedIDs = snoozeManager.snoozedIDs
        return prs.filter { !snoozedIDs.contains($0.id) }
    }

    private func matchesReviewFilter(_ pr: PullRequest, filter: ReviewFilter) -> Bool {
        guard !filter.isAll else { return true }

        let authorRule = filter.authors.first {
            $0.username.caseInsensitiveCompare(pr.author) == .orderedSame
        }
        let repositoryRule = filter.repositories.first {
            $0.repository.caseInsensitiveCompare(pr.repository) == .orderedSame
        }

        let matchingTeamRules = filter.teams.filter { rule in
            pr.requestedTeamKeys.contains {
                $0.caseInsensitiveCompare(rule.team) == .orderedSame
            }
        }

        if authorRule?.isIncluded == false
            || repositoryRule?.isIncluded == false
            || matchingTeamRules.contains(where: { !$0.isIncluded }) {
            return false
        }

        let matchesIncludedAuthor = authorRule?.isIncluded == true
        let matchesIncludedRepository = repositoryRule?.isIncluded == true
        let matchesDirectRequest = filter.includesDirectRequests
            && pr.isDirectReviewRequested

        if matchesIncludedAuthor || matchesIncludedRepository || matchesDirectRequest {
            return true
        }

        if matchingTeamRules.contains(where: \.isIncluded) {
            return true
        }

        // Exclude-only rules are useful blacklists: include everything except
        // the explicitly excluded values. With no positive criteria at all,
        // the filter is unrestricted apart from its exclusions.
        let hasPositiveCriteria = filter.teams.contains { $0.isIncluded }
            || filter.authors.contains { $0.isIncluded }
            || filter.repositories.contains { $0.isIncluded }
        return !hasPositiveCriteria
    }

    private static func loadReviewFilters(from userDefaults: UserDefaults) -> [ReviewFilter] {
        guard let data = userDefaults.data(forKey: "reviewFilters") else { return [] }
        return (try? JSONDecoder().decode([ReviewFilter].self, from: data)) ?? []
    }

    private func persistReviewFilters() {
        guard let data = try? JSONEncoder().encode(customReviewFilters) else { return }
        userDefaults.set(data, forKey: "reviewFilters")
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

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { version in
            version.split(separator: ".").compactMap { Int($0) }
        }
        let candidateParts = parse(candidate)
        let currentParts = parse(current)
        let count = max(candidateParts.count, currentParts.count)
        for i in 0 ..< count {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let v = i < currentParts.count ? currentParts[i] : 0
            if c > v { return true }
            if c < v { return false }
        }
        return false
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
                updatedAt: Date().addingTimeInterval(-3600),
                isDraft: false,
                reviewDecision: nil,
                viewerDidApprove: false,
                hasAnyApproval: false,
                additions: 250,
                deletions: 40,
                changedFiles: 8,
                totalComments: 5,
                reviewers: [
                    Reviewer(kind: .user, id: "bob", displayName: "bob", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4")),
                    Reviewer(kind: .user, id: "carol", displayName: "carol", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/3?v=4")),
                ]
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
                updatedAt: Date().addingTimeInterval(-1800),
                isDraft: false,
                reviewDecision: nil,
                viewerDidApprove: false,
                hasAnyApproval: false,
                additions: 12,
                deletions: 3,
                changedFiles: 2,
                totalComments: 0,
                reviewers: []
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
                updatedAt: Date().addingTimeInterval(-600),
                isDraft: false,
                reviewDecision: nil,
                viewerDidApprove: false,
                hasAnyApproval: false,
                additions: 88,
                deletions: 15,
                changedFiles: 4,
                totalComments: 2,
                reviewers: [
                    Reviewer(kind: .user, id: "alice", displayName: "alice", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4")),
                    Reviewer(
                        kind: .team,
                        id: "platform",
                        displayName: "Platform Team",
                        avatarURL: URL(string: "https://avatars.githubusercontent.com/t/1?v=4")
                    ),
                    Reviewer(kind: .user, id: "eve", displayName: "eve", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/5?v=4")),
                    Reviewer(kind: .user, id: "frank", displayName: "frank", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/6?v=4")),
                ]
            )
        ]
        state.lastUpdated = Date()
        state.ghAuthStatus = .authenticated(login: "previewer")
        return state
    }
}

#if DEBUG
    extension AppState {
        func resetNotificationTracking() {
            notifiedPRIds.removeAll()
            previousApprovedIds.removeAll()
            previousChangesRequestedIds.removeAll()
            isFirstLoad = false
        }

        func sendTestReviewRequestedNotification() {
            scheduleTestNotification(title: "Needs my review", attachment: Self.createReviewRequestedIconAttachment())
        }

        func sendTestApprovedNotification() {
            scheduleTestNotification(title: "Approved", attachment: Self.createApprovedIconAttachment())
        }

        func sendTestChangesRequestedNotification() {
            scheduleTestNotification(title: "Returned to me", attachment: Self.createChangesRequestedIconAttachment())
        }

        private func scheduleTestNotification(title: String, attachment: UNNotificationAttachment?) {
            NSApp.deactivate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let content = UNMutableNotificationContent()
                content.title = title
                content.subtitle = "acme/widgets #1234"
                content.body = "feat: Add dark mode support for dashboard"
                content.sound = .default
                if let attachment { content.attachments = [attachment] }
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
#endif

enum GHAuthStatus: Equatable {
    case unknown
    case ghMissing
    case notAuthenticated
    case authenticated(login: String)

    var isHealthy: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .ghMissing: GitHubService.GitHubError.ghNotInstalled.errorDescription
        case .notAuthenticated: GitHubService.GitHubError.ghNotAuthenticated.errorDescription
        case .unknown, .authenticated: nil
        }
    }
}
