@testable import PRMonitor
import XCTest

// MARK: - GHCommand Mock

/// Routes `gh api` calls to canned responses based on the GraphQL query passed via stdin.
private final actor MockGHCommand: GHCommandProtocol {
    typealias Handler = @Sendable (_ arguments: [String], _ stdin: Data?) -> Result<Data, GHCommand.GHError>?

    private var handlers: [Handler] = []
    private(set) var callCount = 0

    func install(handlers: [Handler]) {
        self.handlers = handlers
    }

    func resolveBinary() async throws -> URL {
        URL(fileURLWithPath: "/mock/gh")
    }

    func invalidatePath() async {}

    func run(arguments: [String], stdin: Data?, timeout _: TimeInterval) async throws -> GHCommand.RunResult {
        let data = try await runExpectingSuccess(arguments: arguments, stdin: stdin, timeout: 0)
        return GHCommand.RunResult(exitCode: 0, stdout: data, stderr: "")
    }

    func runExpectingSuccess(arguments: [String], stdin: Data?, timeout _: TimeInterval) async throws -> Data {
        callCount += 1
        for handler in handlers {
            if let result = handler(arguments, stdin) {
                switch result {
                case let .success(data): return data
                case let .failure(error): throw error
                }
            }
        }
        throw GHCommand.GHError.nonZeroExit(code: 1, stderr: "no mock handler matched")
    }
}

// MARK: - Helpers

/// Build a GraphQL JSON response with the given PR nodes.
private func graphQLJSON(nodes: [[String: Any]]) -> Data {
    let body: [String: Any] = [
        "data": [
            "viewer": ["login": "tester"],
            "search": [
                "nodes": nodes,
            ],
        ],
    ]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: body)
}

/// Build a single PR node dictionary.
private func prNode(
    id: String,
    number: Int,
    title: String,
    url: String = "https://github.com/owner/repo/pull/1",
    isDraft: Bool = false,
    reviewDecision: String? = nil,
    author: String = "alice",
    repo: String = "owner/repo",
    createdAt: String = "2025-01-15T10:00:00Z",
    updatedAt: String = "2025-01-15T12:00:00Z",
    additions: Int = 0,
    deletions: Int = 0,
    changedFiles: Int = 0,
    totalCommentsCount: Int = 0,
    reviewRequests: [[String: Any]] = [],
    latestReviews: [[String: Any]] = []
) -> [String: Any] {
    var node: [String: Any] = [
        "id": id,
        "number": number,
        "title": title,
        "url": url,
        "isDraft": isDraft,
        "createdAt": createdAt,
        "updatedAt": updatedAt,
        "author": ["login": author, "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4"],
        "repository": ["nameWithOwner": repo],
        "additions": additions,
        "deletions": deletions,
        "changedFiles": changedFiles,
        "totalCommentsCount": totalCommentsCount,
        "reviewRequests": ["nodes": reviewRequests],
        "latestReviews": ["nodes": latestReviews],
    ]
    if let decision = reviewDecision {
        node["reviewDecision"] = decision
    }
    return node
}

/// Extract the GraphQL query string from the stdin payload that `fetchPRs` sends.
private func queryString(from stdin: Data?) -> String? {
    guard let stdin else { return nil }
    return String(data: stdin, encoding: .utf8)
}

/// Install handlers for the three queries used by `fetchAllPRs`.
private func installHandlers(
    on mock: MockGHCommand,
    reviewRequested: [[String: Any]],
    authored: [[String: Any]],
    reviewed: [[String: Any]]
) async {
    // Pre-serialize so the @Sendable handlers only capture Sendable Data.
    let reviewRequestedData = graphQLJSON(nodes: reviewRequested)
    let authoredData = graphQLJSON(nodes: authored)
    let reviewedData = graphQLJSON(nodes: reviewed)

    let handlers: [MockGHCommand.Handler] = [
        { args, stdin in
            guard args.contains("graphql"),
                  let q = queryString(from: stdin),
                  q.contains("review-requested:@me") else { return nil }
            return .success(reviewRequestedData)
        },
        { args, stdin in
            guard args.contains("graphql"),
                  let q = queryString(from: stdin),
                  q.contains("reviewed-by:@me") else { return nil }
            return .success(reviewedData)
        },
        { args, stdin in
            guard args.contains("graphql"),
                  let q = queryString(from: stdin),
                  q.contains("author:@me") else { return nil }
            return .success(authoredData)
        },
    ]
    await mock.install(handlers: handlers)
}

// MARK: - Tests

final class GitHubServiceTests: XCTestCase {
    // MARK: PR Categorization

    func testValidResponseCategorizesCorrectly() async throws {
        let reviewRequested = prNode(
            id: "pr-1", number: 1, title: "Review me", reviewDecision: nil,
            additions: 150, deletions: 30, changedFiles: 5, totalCommentsCount: 3
        )
        let authorApproved = prNode(id: "pr-2", number: 2, title: "Approved PR", reviewDecision: "APPROVED")
        let authorChanges = prNode(id: "pr-3", number: 3, title: "Changes PR", reviewDecision: "CHANGES_REQUESTED")
        let authorWaiting = prNode(id: "pr-4", number: 4, title: "Waiting PR", reviewDecision: "REVIEW_REQUIRED")
        let reviewed = prNode(id: "pr-5", number: 5, title: "Reviewed by me")

        let mock = MockGHCommand()
        await installHandlers(
            on: mock,
            reviewRequested: [reviewRequested],
            authored: [authorApproved, authorChanges, authorWaiting],
            reviewed: [reviewed]
        )

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-1")

        let pr1 = try XCTUnwrap(results.needsReview.first)
        XCTAssertEqual(pr1.additions, 150)
        XCTAssertEqual(pr1.deletions, 30)
        XCTAssertEqual(pr1.changedFiles, 5)
        XCTAssertEqual(pr1.totalComments, 3)

        XCTAssertEqual(results.approved.count, 1)
        XCTAssertEqual(results.approved.first?.id, "pr-2")

        XCTAssertEqual(results.changesRequested.count, 1)
        XCTAssertEqual(results.changesRequested.first?.id, "pr-3")

        XCTAssertEqual(results.waitingForReviewers.count, 1)
        XCTAssertEqual(results.waitingForReviewers.first?.id, "pr-4")

        XCTAssertEqual(results.myChangesRequested.count, 1)
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-5")
    }

    // MARK: Draft Exclusion

    func testAuthoredDraftsAreExcluded() async throws {
        let draft = prNode(id: "pr-draft", number: 10, title: "Draft PR", isDraft: true)
        let nonDraft = prNode(id: "pr-nondraft", number: 11, title: "Non-draft PR", reviewDecision: "REVIEW_REQUIRED")

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [], authored: [draft, nonDraft], reviewed: [])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.approved.count, 0)
        XCTAssertEqual(results.changesRequested.count, 0)
        XCTAssertEqual(results.waitingForReviewers.count, 1)
        XCTAssertEqual(results.waitingForReviewers.first?.id, "pr-nondraft")

        XCTAssertEqual(results.drafts.count, 1)
        XCTAssertEqual(results.drafts.first?.id, "pr-draft")
    }

    // MARK: Dedup in myChangesRequested

    func testMyChangesRequestedDeduplicates() async throws {
        let sharedPR = prNode(id: "pr-shared", number: 20, title: "Shared PR", reviewDecision: "CHANGES_REQUESTED")

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [sharedPR], authored: [], reviewed: [sharedPR])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.myChangesRequested.count, 1)
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-shared")
        XCTAssertEqual(results.needsReview.count, 0)
    }

    // MARK: API Error

    func testAPIErrorThrows() async throws {
        let errorJSON: [String: Any] = [
            "errors": [["message": "Bad credentials"]],
        ]
        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)

        let mock = MockGHCommand()
        await mock.install(handlers: [{ _, _ in .success(errorData) }])

        let service = GitHubService(gh: mock)
        do {
            _ = try await service.fetchAllPRs()
            XCTFail("Expected apiError to be thrown")
        } catch let error as GitHubService.GitHubError {
            if case let .apiError(message) = error {
                XCTAssertEqual(message, "Bad credentials")
            } else {
                XCTFail("Expected .apiError, got \(error)")
            }
        }
    }

    // MARK: Subprocess failure surfaces as subprocessFailed

    func testSubprocessFailureThrows() async throws {
        let mock = MockGHCommand()
        await mock.install(handlers: [
            { _, _ in .failure(.nonZeroExit(code: 1, stderr: "API rate limit exceeded")) },
        ])

        let service = GitHubService(gh: mock)
        do {
            _ = try await service.fetchAllPRs()
            XCTFail("Expected subprocessFailed to be thrown")
        } catch let error as GitHubService.GitHubError {
            if case let .subprocessFailed(message) = error {
                XCTAssertTrue(message.contains("rate limit"))
            } else {
                XCTFail("Expected .subprocessFailed, got \(error)")
            }
        }
    }

    // MARK: Authentication error mapping

    func testAuthErrorMapsToNotAuthenticated() async throws {
        let mock = MockGHCommand()
        await mock.install(handlers: [
            { _, _ in .failure(.nonZeroExit(code: 1, stderr: "authentication required")) },
        ])

        let service = GitHubService(gh: mock)
        do {
            _ = try await service.fetchAllPRs()
            XCTFail("Expected ghNotAuthenticated to be thrown")
        } catch let error as GitHubService.GitHubError {
            if case .ghNotAuthenticated = error {
                // expected
            } else {
                XCTFail("Expected .ghNotAuthenticated, got \(error)")
            }
        }
    }

    // MARK: Re-requested Review Exclusion

    func testReReviewRequestedExcludedFromReviewed() async throws {
        let reRequested = prNode(id: "pr-rerequested", number: 40, title: "Re-requested PR", reviewDecision: "REVIEW_REQUIRED")

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [reRequested], authored: [], reviewed: [reRequested])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-rerequested")
        XCTAssertEqual(results.myChangesRequested.count, 0)
    }

    // MARK: Already-approved PR drops out of needsReview, lands in Reviewed

    func testNeedsReviewExcludesPRsWithExistingApproval() async throws {
        // Repo without branch protection: reviewDecision is null, but someone has already approved.
        // The viewer is still a requested reviewer but shouldn't be nagged.
        let approvedReview: [String: Any] = [
            "state": "APPROVED",
            "author": ["login": "andy", "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4"],
        ]
        let pr = prNode(
            id: "pr-already-approved",
            number: 207,
            title: "feat: thing someone else approved",
            reviewDecision: nil,
            latestReviews: [approvedReview]
        )

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [pr], authored: [], reviewed: [])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.needsReview.count, 0, "PRs with any approval should not appear in needsReview")
        XCTAssertEqual(results.myChangesRequested.count, 1, "Approved-by-someone-else PRs land in Reviewed")
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-already-approved")
    }

    // MARK: PRs I approved show up in Reviewed (not hidden)

    func testReviewedIncludesPRsIApproved() async throws {
        // I approved a PR. It should show in "Reviewed" so I can track it, not disappear.
        let pr = prNode(id: "pr-i-approved", number: 50, title: "Thing I approved", reviewDecision: nil)

        let mock = MockGHCommand()
        // The reviewed-by:@me query returns it (since the -review:approved exclusion is gone).
        await installHandlers(on: mock, reviewRequested: [], authored: [], reviewed: [pr])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.myChangesRequested.count, 1)
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-i-approved")
        XCTAssertEqual(results.needsReview.count, 0)
    }

    func testNeedsReviewIncludesPRsWithOnlyComments() async throws {
        // Same shape as above but the existing review is just a comment, not an approval.
        // Comment reviews don't change PR state, so the viewer still needs to review.
        let commentReview: [String: Any] = [
            "state": "COMMENTED",
            "author": ["login": "jp", "avatarUrl": "https://avatars.githubusercontent.com/u/2?v=4"],
        ]
        let pr = prNode(
            id: "pr-only-commented",
            number: 208,
            title: "feat: thing only commented on",
            reviewDecision: nil,
            latestReviews: [commentReview]
        )

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [pr], authored: [], reviewed: [])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-only-commented")
        XCTAssertEqual(results.myChangesRequested.count, 0, "Comment-only PRs don't move to Reviewed")
    }

    // MARK: Team Reviewers

    func testReviewerParsingHandlesTeamsAndUsers() async throws {
        let userReq: [String: Any] = [
            "requestedReviewer": [
                "__typename": "User",
                "login": "alice",
                "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4",
            ],
        ]
        let teamReq: [String: Any] = [
            "requestedReviewer": [
                "__typename": "Team",
                "slug": "frontend",
                "name": "Frontend Team",
                "avatarUrl": "https://avatars.githubusercontent.com/t/1?v=4",
            ],
        ]
        let collidingUserReq: [String: Any] = [
            "requestedReviewer": [
                "__typename": "User",
                "login": "frontend",
                "avatarUrl": "https://avatars.githubusercontent.com/u/2?v=4",
            ],
        ]

        let pr = prNode(
            id: "pr-team", number: 50, title: "Team review",
            reviewRequests: [userReq, teamReq, collidingUserReq]
        )

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [pr], authored: [], reviewed: [])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        let reviewers = try XCTUnwrap(results.needsReview.first).reviewers
        XCTAssertEqual(reviewers.count, 3)

        let alice = try XCTUnwrap(reviewers.first { $0.id == "alice" && $0.kind == .user })
        XCTAssertEqual(alice.displayName, "alice")

        let team = try XCTUnwrap(reviewers.first { $0.id == "frontend" && $0.kind == .team })
        XCTAssertEqual(team.displayName, "Frontend Team")

        let userFrontend = try XCTUnwrap(reviewers.first { $0.id == "frontend" && $0.kind == .user })
        XCTAssertEqual(userFrontend.displayName, "frontend")
    }

    func testReviewRequestSourcesAreParsed() async throws {
        let directRequest: [String: Any] = [
            "requestedReviewer": [
                "__typename": "User",
                "login": "tester",
            ],
        ]
        let teamRequest: [String: Any] = [
            "requestedReviewer": [
                "__typename": "Team",
                "slug": "platform",
                "name": "Platform",
                "organization": ["login": "acme"],
            ],
        ]
        let pr = prNode(
            id: "pr-sources",
            number: 51,
            title: "Request sources",
            reviewRequests: [directRequest, teamRequest]
        )

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [pr], authored: [], reviewed: [])

        let results = try await GitHubService(gh: mock).fetchAllPRs()
        let parsed = try XCTUnwrap(results.needsReview.first)

        XCTAssertTrue(parsed.isDirectReviewRequested)
        XCTAssertEqual(parsed.requestedTeamKeys, ["acme/platform"])
    }

    // MARK: needsReview vs Reviewed split by PR state

    func testNeedsReviewFiltersApprovedAndChangesRequested() async throws {
        // Three PRs the viewer is requested on, each in a different PR-level state.
        // Pending → Needs my review. Approved or ChangesRequested → Reviewed.
        let approvedPR = prNode(id: "pr-a", number: 30, title: "Approved review-requested", reviewDecision: "APPROVED")
        let changesPR = prNode(id: "pr-b", number: 31, title: "Changes review-requested", reviewDecision: "CHANGES_REQUESTED")
        let pendingPR = prNode(id: "pr-c", number: 32, title: "Pending review-requested")

        let mock = MockGHCommand()
        await installHandlers(on: mock, reviewRequested: [approvedPR, changesPR, pendingPR], authored: [], reviewed: [])

        let service = GitHubService(gh: mock)
        let results = try await service.fetchAllPRs()

        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-c")

        let reviewedIDs = Set(results.myChangesRequested.map(\.id))
        XCTAssertEqual(reviewedIDs, ["pr-a", "pr-b"], "Approved and changes-requested PRs both land in Reviewed")
    }
}
