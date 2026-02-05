@testable import PRMonitor
import XCTest

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
        isDraft: false,
        reviewDecision: reviewDecision,
        additions: 0,
        deletions: 0,
        changedFiles: 0,
        totalComments: 0
    )
}

// MARK: - Tests

@MainActor
final class AppStateTests: XCTestCase {
    private var mockService: MockGitHubService!
    private var appState: AppState!

    override func setUp() {
        super.setUp()
        mockService = MockGitHubService()
        appState = AppState(service: mockService, startAutomatically: false)
    }

    override func tearDown() {
        appState = nil
        mockService = nil
        super.tearDown()
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
        await mockService.configure(error: GitHubService.GitHubError.noToken)
        await appState.refresh()

        XCTAssertNotNil(appState.error)
        XCTAssertTrue(try XCTUnwrap(appState.error?.contains("No GitHub token")))
    }

    // MARK: refresh() clears error on success

    func testRefreshClearsErrorOnSuccess() async {
        // First, set an error
        await mockService.configure(error: GitHubService.GitHubError.noToken)
        await appState.refresh()
        XCTAssertNotNil(appState.error)

        // Then succeed
        await mockService.configure(result: PRFetchResults())
        await appState.refresh()
        XCTAssertNil(appState.error)
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
