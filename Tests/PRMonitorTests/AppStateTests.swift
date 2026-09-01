@testable import PRMonitor
@preconcurrency import XCTest

// MARK: - Mock Service

private actor MockGitHubService: GitHubServiceProtocol {
    var resultToReturn: PRFetchResults?
    var errorToThrow: Error?
    var fetchCallCount = 0

    func configure(result: PRFetchResults) {
        resultToReturn = result
        errorToThrow = nil
    }

    func configure(error: Error) {
        errorToThrow = error
        resultToReturn = nil
    }

    func fetchAllPRs() async throws -> PRFetchResults {
        fetchCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return resultToReturn ?? PRFetchResults()
    }

    func fetchLatestRelease() async throws -> String? {
        nil
    }
}

// MARK: - Mock GHCommand

private final actor MockGHCommand: GHCommandProtocol {
    enum Mode {
        case authenticated(login: String)
        case notAuthenticated
        case missing
    }

    var mode: Mode = .authenticated(login: "tester")

    func setMode(_ mode: Mode) {
        self.mode = mode
    }

    func resolveBinary() async throws -> URL {
        switch mode {
        case .missing: throw GHCommand.GHError.ghNotFound
        case .authenticated, .notAuthenticated:
            return URL(fileURLWithPath: "/mock/gh")
        }
    }

    func invalidatePath() async {}

    func run(arguments _: [String], stdin _: Data?, timeout _: TimeInterval) async throws -> GHCommand.RunResult {
        let data = try await runExpectingSuccess(arguments: [], stdin: nil, timeout: 0)
        return GHCommand.RunResult(exitCode: 0, stdout: data, stderr: "")
    }

    func runExpectingSuccess(arguments _: [String], stdin _: Data?, timeout _: TimeInterval) async throws -> Data {
        switch mode {
        case let .authenticated(login):
            return Data(login.utf8)
        case .notAuthenticated:
            throw GHCommand.GHError.nonZeroExit(code: 1, stderr: "authentication required")
        case .missing:
            throw GHCommand.GHError.ghNotFound
        }
    }
}

// MARK: - Helpers

private func makePR(
    id: String,
    number: Int = 1,
    title: String = "Test PR",
    author: String = "alice",
    repository: String = "owner/repo",
    reviewDecision: PullRequest.ReviewDecision? = nil,
    isDirectReviewRequested: Bool = false,
    viewerDidReview: Bool = false,
    requestedTeamKeys: Set<String> = []
) -> PullRequest {
    PullRequest(
        id: id,
        number: number,
        title: title,
        // swiftformat:disable:next noForceUnwrapInTests
        url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
        repository: repository,
        author: author,
        authorAvatarURL: nil,
        createdAt: Date(),
        updatedAt: Date(),
        isDraft: false,
        reviewDecision: reviewDecision,
        viewerDidApprove: false,
        hasAnyApproval: false,
        additions: 0,
        deletions: 0,
        changedFiles: 0,
        totalComments: 0,
        reviewers: [],
        viewerDidReview: viewerDidReview,
        isDirectReviewRequested: isDirectReviewRequested,
        requestedTeamKeys: requestedTeamKeys
    )
}

// MARK: - Tests

@MainActor
final class AppStateTests: XCTestCase {
    private var mockService: MockGitHubService!
    private var mockGH: MockGHCommand!
    private var appState: AppState!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        userDefaultsSuiteName = "PRMonitorTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName))
        mockService = MockGitHubService()
        mockGH = MockGHCommand()
        appState = AppState(
            service: mockService,
            gh: mockGH,
            startAutomatically: false,
            userDefaults: userDefaults
        )
        // Default: tests run as if gh CLI is healthy.
        appState.ghAuthStatus = .authenticated(login: "tester")
    }

    override func tearDown() async throws {
        appState = nil
        mockService = nil
        mockGH = nil
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        userDefaults = nil
        userDefaultsSuiteName = nil
        try await super.tearDown()
    }

    // MARK: refresh() populates properties

    func testRefreshPopulatesAllProperties() async {
        var results = PRFetchResults()
        results.needsReview = [makePR(id: "nr-1")]
        results.waitingForReviewers = [makePR(id: "wfr-1")]
        results.approved = [makePR(id: "app-1")]
        results.changesRequested = [makePR(id: "cr-1")]
        results.myChangesRequested = [makePR(id: "mcr-1")]
        results.drafts = [makePR(id: "d-1")]

        await mockService.configure(result: results)
        await appState.refresh()

        XCTAssertEqual(appState.needsReview.count, 1)
        XCTAssertEqual(appState.needsReview.first?.id, "nr-1")

        XCTAssertEqual(appState.waitingForReviewers.count, 1)
        XCTAssertEqual(appState.waitingForReviewers.first?.id, "wfr-1")

        XCTAssertEqual(appState.approved.count, 1)
        XCTAssertEqual(appState.approved.first?.id, "app-1")

        XCTAssertEqual(appState.changesRequested.count, 1)
        XCTAssertEqual(appState.changesRequested.first?.id, "cr-1")

        XCTAssertEqual(appState.myChangesRequested.count, 1)
        XCTAssertEqual(appState.myChangesRequested.first?.id, "mcr-1")

        XCTAssertEqual(appState.drafts.count, 1)
        XCTAssertEqual(appState.drafts.first?.id, "d-1")
    }

    // MARK: refresh() sets lastUpdated

    func testRefreshSetsLastUpdated() async {
        XCTAssertNil(appState.lastUpdated)

        await mockService.configure(result: PRFetchResults())
        await appState.refresh()

        XCTAssertNotNil(appState.lastUpdated)
    }

    // MARK: refresh() sets error on failure

    func testRefreshSetsErrorOnFailure() async throws {
        await mockService.configure(error: GitHubService.GitHubError.ghNotAuthenticated)
        await appState.refresh()

        XCTAssertNotNil(appState.error)
        XCTAssertTrue(try XCTUnwrap(appState.error?.contains("gh auth login")))
    }

    // MARK: refresh() clears error on success

    func testRefreshClearsErrorOnSuccess() async {
        // First, set an error
        await mockService.configure(error: GitHubService.GitHubError.ghNotAuthenticated)
        await appState.refresh()
        XCTAssertNotNil(appState.error)

        // Then succeed
        await mockService.configure(result: PRFetchResults())
        await appState.refresh()
        XCTAssertNil(appState.error)
    }

    // MARK: refresh() short-circuits when gh missing

    func testRefreshShortCircuitsWhenGHMissing() async {
        appState.ghAuthStatus = .ghMissing
        await mockGH.setMode(.missing)
        await mockService.configure(result: PRFetchResults())

        await appState.refresh()

        let callCount = await mockService.fetchCallCount
        XCTAssertEqual(callCount, 0, "Service should not be called when gh is missing")
        XCTAssertNotNil(appState.error)
        XCTAssertTrue(appState.error?.contains("brew install gh") ?? false)
    }

    // MARK: refreshAuthStatus()

    func testRefreshAuthStatusAuthenticated() async {
        await mockGH.setMode(.authenticated(login: "octocat"))
        await appState.refreshAuthStatus()

        XCTAssertEqual(appState.ghAuthStatus, .authenticated(login: "octocat"))
    }

    func testRefreshAuthStatusMissing() async {
        await mockGH.setMode(.missing)
        await appState.refreshAuthStatus()

        XCTAssertEqual(appState.ghAuthStatus, .ghMissing)
    }

    func testRefreshAuthStatusNotAuthenticated() async {
        await mockGH.setMode(.notAuthenticated)
        await appState.refreshAuthStatus()

        XCTAssertEqual(appState.ghAuthStatus, .notAuthenticated)
    }

    // MARK: refresh() guards against concurrent loads

    func testRefreshGuardsConcurrentLoads() async {
        var results = PRFetchResults()
        results.needsReview = [makePR(id: "should-not-appear")]
        await mockService.configure(result: results)

        // Simulate an already in-flight refresh
        appState.isLoading = true

        // This call should bail out immediately due to the guard
        await appState.refresh()

        // Service should never have been called
        let callCount = await mockService.fetchCallCount
        XCTAssertEqual(callCount, 0)

        // Properties should not have been updated
        XCTAssertTrue(appState.needsReview.isEmpty)
        XCTAssertNil(appState.lastUpdated)
    }

    // MARK: bindingForSection

    func testBindingForSectionReads() {
        // Default: needsReview should be expanded
        let binding = appState.bindingForSection("needsReview")
        XCTAssertTrue(binding.wrappedValue)

        // Default: approved should be collapsed
        let approvedBinding = appState.bindingForSection("approved")
        XCTAssertFalse(approvedBinding.wrappedValue)
    }

    func testBindingForSectionWrites() {
        let binding = appState.bindingForSection("needsReview")
        XCTAssertTrue(binding.wrappedValue)

        binding.wrappedValue = false
        XCTAssertEqual(appState.expandedSections["needsReview"], false)
    }

    func testBindingForSectionDefaultsToTrueForUnknownKey() {
        let binding = appState.bindingForSection("unknownSection")
        XCTAssertTrue(binding.wrappedValue)
    }

    // MARK: needsReviewCount

    func testNeedsReviewCount() async {
        var results = PRFetchResults()
        results.needsReview = [makePR(id: "1"), makePR(id: "2"), makePR(id: "3")]

        await mockService.configure(result: results)
        await appState.refresh()

        XCTAssertEqual(appState.needsReviewCount, 3)
    }

    func testAllAndCustomFilterShowExpectedRequests() {
        appState.needsReview = [
            makePR(id: "direct", isDirectReviewRequested: true),
            makePR(id: "team", requestedTeamKeys: ["acme/platform"]),
            makePR(id: "non-member", requestedTeamKeys: ["acme/other"]),
        ]

        XCTAssertEqual(Set(appState.visibleNeedsReview.map(\.id)), ["direct", "team", "non-member"])

        selectPlatformFilter()
        XCTAssertEqual(Set(appState.visibleNeedsReview.map(\.id)), ["direct", "team"])
    }

    func testCustomFilterIncludesSelectedTeamsAndDirectRequests() {
        appState.needsReview = [
            makePR(id: "team-only", requestedTeamKeys: ["acme/platform"]),
            makePR(id: "direct", isDirectReviewRequested: true),
            makePR(
                id: "direct-and-team",
                isDirectReviewRequested: true,
                requestedTeamKeys: ["acme/platform"]
            ),
        ]

        XCTAssertEqual(
            Set(appState.visibleNeedsReview.map(\.id)),
            ["team-only", "direct", "direct-and-team"]
        )

        selectPlatformFilter()
        XCTAssertEqual(
            Set(appState.visibleNeedsReview.map(\.id)),
            ["team-only", "direct", "direct-and-team"]
        )
    }

    func testCustomFilterMatchesMemberTeamAmongMultipleRequests() {
        appState.needsReview = [
            makePR(id: "multiple-teams", requestedTeamKeys: ["acme/platform", "acme/other"]),
        ]

        selectPlatformFilter()
        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["multiple-teams"])
    }

    func testTeamRulesMatchExplicitTeamKeys() {
        appState.needsReview = [
            makePR(id: "platform", requestedTeamKeys: ["acme/platform"]),
            makePR(id: "other", requestedTeamKeys: ["acme/other"]),
        ]

        let filter = ReviewFilter(
            id: "all-teams",
            name: "All teams",
            includesDirectRequests: false,
            teams: [ReviewFilterTeam(team: "acme/platform", isIncluded: true)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["platform"])
    }

    func testTeamRulesSupportIncludeAndExclude() {
        appState.needsReview = [
            makePR(id: "included", requestedTeamKeys: ["acme/platform"]),
            makePR(
                id: "excluded",
                isDirectReviewRequested: true,
                requestedTeamKeys: ["acme/releases"]
            ),
            makePR(id: "not-selected", requestedTeamKeys: ["acme/other"]),
        ]

        let filter = ReviewFilter(
            id: "team-rules",
            name: "Team rules",
            includesDirectRequests: true,
            teams: [
                ReviewFilterTeam(team: "acme/platform", isIncluded: true),
                ReviewFilterTeam(team: "acme/releases", isIncluded: false),
            ]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["included"])
    }

    func testCustomFilterMatchesSelectedUsernames() {
        appState.needsReview = [
            makePR(id: "selected", author: "perchwell-release-please[bot]"),
            makePR(id: "not-selected", author: "someone-else"),
        ]

        let filter = ReviewFilter(
            id: "bot-filter",
            name: "Release bot",
            includesDirectRequests: false,
            teams: [],
            authors: [ReviewFilterAuthor(username: "perchwell-release-please[bot]", isIncluded: true)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["selected"])
    }

    func testCustomFilterMatchesIncludedAndExcludedRepositories() {
        appState.needsReview = [
            makePR(id: "included", repository: "RivingtonHoldings/athens"),
            makePR(id: "excluded", repository: "RivingtonHoldings/releases"),
            makePR(id: "not-selected", repository: "RivingtonHoldings/widgets"),
        ]

        let filter = ReviewFilter(
            id: "repository-filter",
            name: "Repositories",
            includesDirectRequests: false,
            teams: [],
            repositories: [
                ReviewFilterRepository(repository: "rivingtonholdings/athens", isIncluded: true),
                ReviewFilterRepository(repository: "rivingtonholdings/releases", isIncluded: false),
            ]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["included"])
    }

    func testExcludedAuthorOverridesOtherFilterMatches() {
        appState.needsReview = [
            makePR(
                id: "excluded",
                author: "release-bot",
                isDirectReviewRequested: true,
                requestedTeamKeys: ["acme/platform"]
            ),
            makePR(id: "included", author: "another-author", requestedTeamKeys: ["acme/platform"]),
        ]

        let filter = ReviewFilter(
            id: "author-filter",
            name: "Author rules",
            includesDirectRequests: true,
            teams: [ReviewFilterTeam(team: "acme/platform", isIncluded: true)],
            authors: [ReviewFilterAuthor(username: "release-bot", isIncluded: false)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["included"])
    }

    func testExcludeOnlyAuthorFilterKeepsOtherAuthors() {
        appState.needsReview = [
            makePR(id: "release", author: "perchwell-release-please[bot]"),
            makePR(id: "feature", author: "alice"),
        ]

        let filter = ReviewFilter(
            id: "without-releases",
            name: "Without releases",
            includesDirectRequests: true,
            teams: [],
            authors: [ReviewFilterAuthor(username: "perchwell-release-please[bot]", isIncluded: false)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["feature"])
    }

    func testFilterAppliesToAllSectionsAndCounts() {
        appState.needsReview = [
            makePR(id: "needs-alice", author: "alice"),
            makePR(id: "needs-bob", author: "bob"),
        ]
        appState.waitingForReviewers = [
            makePR(id: "waiting-alice", author: "alice"),
            makePR(id: "waiting-bob", author: "bob"),
        ]
        appState.approved = [
            makePR(id: "approved-alice", author: "alice"),
            makePR(id: "approved-bob", author: "bob"),
        ]
        appState.changesRequested = [
            makePR(id: "changes-alice", author: "alice"),
            makePR(id: "changes-bob", author: "bob"),
        ]
        appState.myChangesRequested = [
            makePR(id: "reviewed-alice", author: "alice"),
            makePR(id: "reviewed-bob", author: "bob"),
        ]
        appState.drafts = [
            makePR(id: "draft-alice", author: "alice"),
            makePR(id: "draft-bob", author: "bob"),
        ]

        let filter = ReviewFilter(
            id: "alice",
            name: "Alice",
            includesDirectRequests: false,
            teams: [],
            authors: [ReviewFilterAuthor(username: "alice", isIncluded: true)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["needs-alice"])
        XCTAssertEqual(Set(appState.visibleWaitingForReviewers.map(\.id)), ["waiting-alice", "waiting-bob"])
        XCTAssertEqual(Set(appState.visibleApproved.map(\.id)), ["approved-alice", "approved-bob"])
        XCTAssertEqual(Set(appState.visibleChangesRequested.map(\.id)), ["changes-alice", "changes-bob"])
        XCTAssertEqual(appState.visibleMyChangesRequested.map(\.id), ["reviewed-alice"])
        XCTAssertEqual(Set(appState.visibleDrafts.map(\.id)), ["draft-alice", "draft-bob"])

        let counts = appState.counts(for: filter)
        XCTAssertEqual(counts.needsReview, 1)
        XCTAssertEqual(counts.approved, 2)
        XCTAssertEqual(counts.changesRequested, 2)
    }

    func testTeamRuleDoesNotMatchOtherTeams() {
        appState.needsReview = [
            makePR(id: "member", requestedTeamKeys: ["acme/platform"]),
            makePR(id: "non-member", requestedTeamKeys: ["acme/other"]),
        ]

        XCTAssertEqual(Set(appState.visibleNeedsReview.map(\.id)), ["member", "non-member"])

        selectPlatformFilter()

        XCTAssertEqual(appState.visibleNeedsReview.map(\.id), ["member"])
    }

    func testFilteredAppliesToReviewedSection() {
        appState.myChangesRequested = [
            makePR(id: "reviewed-by-me", viewerDidReview: true),
            makePR(id: "team-review", requestedTeamKeys: ["acme/platform"]),
            makePR(id: "non-member-team", requestedTeamKeys: ["acme/other"]),
        ]

        XCTAssertEqual(Set(appState.visibleMyChangesRequested.map(\.id)), [
            "reviewed-by-me",
            "team-review",
            "non-member-team",
        ])

        selectPlatformFilter()

        XCTAssertEqual(
            Set(appState.visibleMyChangesRequested.map(\.id)),
            ["team-review"]
        )
    }

    func testReviewFiltersPersistAcrossAppStateInstances() {
        let filter = ReviewFilter(
            id: "persisted-filter",
            name: "Persisted",
            includesDirectRequests: true,
            teams: [ReviewFilterTeam(team: "acme/platform", isIncluded: true)],
            repositories: [ReviewFilterRepository(repository: "acme/widgets", isIncluded: true)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)

        let reloadedState = AppState(
            service: mockService,
            gh: mockGH,
            startAutomatically: false,
            userDefaults: userDefaults
        )

        XCTAssertEqual(reloadedState.customReviewFilters, [filter])
        XCTAssertEqual(reloadedState.activeReviewFilter, filter)
    }

    func testReviewFilterPersistsAuthorModes() throws {
        let filter = ReviewFilter(
            id: "author-rules",
            name: "Author rules",
            includesDirectRequests: false,
            teams: [],
            authors: [
                ReviewFilterAuthor(username: "release-bot", isIncluded: false),
                ReviewFilterAuthor(username: "alice", isIncluded: true),
            ],
            repositories: [ReviewFilterRepository(repository: "acme/releases", isIncluded: false)]
        )

        let encoded = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(ReviewFilter.self, from: encoded)
        XCTAssertEqual(decoded, filter)
    }

    private func selectPlatformFilter() {
        let filter = ReviewFilter(
            id: "test-filter",
            name: "Platform",
            includesDirectRequests: true,
            teams: [ReviewFilterTeam(team: "acme/platform", isIncluded: true)]
        )
        appState.saveReviewFilter(filter)
        appState.selectReviewFilter(filter)
    }
}
