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
    reviewDecision: PullRequest.ReviewDecision? = nil
) -> PullRequest {
    PullRequest(
        id: id,
        number: number,
        title: title,
        // swiftformat:disable:next noForceUnwrapInTests
        url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
        repository: "owner/repo",
        author: "alice",
        authorAvatarURL: nil,
        createdAt: Date(),
        updatedAt: Date(),
        isDraft: false,
        reviewDecision: reviewDecision,
        viewerDidApprove: false,
        additions: 0,
        deletions: 0,
        changedFiles: 0,
        totalComments: 0,
        reviewers: []
    )
}

// MARK: - Tests

@MainActor
final class AppStateTests: XCTestCase {
    private var mockService: MockGitHubService!
    private var mockGH: MockGHCommand!
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockService = MockGitHubService()
        mockGH = MockGHCommand()
        appState = AppState(service: mockService, gh: mockGH, startAutomatically: false)
        // Default: tests run as if gh CLI is healthy.
        appState.ghAuthStatus = .authenticated(login: "tester")
    }

    override func tearDown() async throws {
        appState = nil
        mockService = nil
        mockGH = nil
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
}
