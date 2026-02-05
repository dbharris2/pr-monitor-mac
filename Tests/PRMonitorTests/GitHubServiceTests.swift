@testable import PRMonitor
import XCTest

// MARK: - URLProtocol Mock

// swiftlint:disable:next static_over_final_class
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [(URLRequest) -> (Data, HTTPURLResponse)?] = []

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        for handler in Self.handlers {
            if let (data, response) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private let graphQLURL = URL(string: "https://api.github.com/graphql")!

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func okResponse() -> HTTPURLResponse {
    HTTPURLResponse(url: graphQLURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private func errorResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: graphQLURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

/// Build a GraphQL JSON response with the given PR nodes.
private func graphQLJSON(nodes: [[String: Any]]) -> Data {
    let body: [String: Any] = [
        "data": [
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
    createdAt: String = "2025-01-15T10:00:00Z"
) -> [String: Any] {
    var node: [String: Any] = [
        "id": id,
        "number": number,
        "title": title,
        "url": url,
        "isDraft": isDraft,
        "createdAt": createdAt,
        "author": ["login": author, "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4"],
        "repository": ["nameWithOwner": repo],
    ]
    if let decision = reviewDecision {
        node["reviewDecision"] = decision
    }
    return node
}

/// Extract the search query string from a URLRequest body.
private func queryString(from request: URLRequest) -> String? {
    let data: Data?
    if let body = request.httpBody {
        data = body
    } else if let stream = request.httpBodyStream {
        stream.open()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var result = Data()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                result.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        stream.close()
        data = result
    } else {
        data = nil
    }
    guard let data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let query = json["query"] as? String
    else { return nil }
    return query
}

/// Install handlers for the three queries used by `fetchAllPRs`.
/// - Parameters:
///   - reviewRequested: Nodes for the "review-requested:@me" query
///   - authored: Nodes for the "author:@me" query
///   - reviewed: Nodes for the "reviewed-by:@me" query
private func installHandlers(
    reviewRequested: [[String: Any]],
    authored: [[String: Any]],
    reviewed: [[String: Any]]
) {
    MockURLProtocol.handlers = [
        { request -> (Data, HTTPURLResponse)? in
            guard let q = queryString(from: request), q.contains("review-requested:@me") else { return nil }
            return (graphQLJSON(nodes: reviewRequested), okResponse())
        },
        { request -> (Data, HTTPURLResponse)? in
            guard let q = queryString(from: request), q.contains("reviewed-by:@me") else { return nil }
            return (graphQLJSON(nodes: reviewed), okResponse())
        },
        { request -> (Data, HTTPURLResponse)? in
            guard let q = queryString(from: request), q.contains("author:@me") else { return nil }
            return (graphQLJSON(nodes: authored), okResponse())
        },
    ]
}

// MARK: - Tests

final class GitHubServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handlers = []
        super.tearDown()
    }

    // MARK: PR Categorization

    func testValidResponseCategorizesCorrectly() async throws {
        // review-requested:@me → one PR with no decision (needs review)
        let reviewRequested = prNode(id: "pr-1", number: 1, title: "Review me", reviewDecision: nil)

        // author:@me → one approved, one changes_requested, one waiting
        let authorApproved = prNode(id: "pr-2", number: 2, title: "Approved PR", reviewDecision: "APPROVED")
        let authorChanges = prNode(id: "pr-3", number: 3, title: "Changes PR", reviewDecision: "CHANGES_REQUESTED")
        let authorWaiting = prNode(id: "pr-4", number: 4, title: "Waiting PR", reviewDecision: "REVIEW_REQUIRED")

        // reviewed-by:@me → one PR I reviewed
        let reviewed = prNode(id: "pr-5", number: 5, title: "Reviewed by me")

        installHandlers(
            reviewRequested: [reviewRequested],
            authored: [authorApproved, authorChanges, authorWaiting],
            reviewed: [reviewed]
        )

        let service = GitHubService(session: makeSession())
        let results = try await service.fetchAllPRs(token: "test-token")

        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-1")

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

        installHandlers(
            reviewRequested: [],
            authored: [draft, nonDraft],
            reviewed: []
        )

        let service = GitHubService(session: makeSession())
        let results = try await service.fetchAllPRs(token: "test-token")

        // Draft should be excluded from all authored categories
        XCTAssertEqual(results.approved.count, 0)
        XCTAssertEqual(results.changesRequested.count, 0)
        XCTAssertEqual(results.waitingForReviewers.count, 1)
        XCTAssertEqual(results.waitingForReviewers.first?.id, "pr-nondraft")
    }

    // MARK: Dedup in myChangesRequested

    func testMyChangesRequestedDeduplicates() async throws {
        // Same PR appears in both reviewed-by and review-requested (with changes_requested)
        let sharedPR = prNode(id: "pr-shared", number: 20, title: "Shared PR", reviewDecision: "CHANGES_REQUESTED")

        installHandlers(
            reviewRequested: [sharedPR],
            authored: [],
            reviewed: [sharedPR]
        )

        let service = GitHubService(session: makeSession())
        let results = try await service.fetchAllPRs(token: "test-token")

        // Should appear only once in myChangesRequested, not twice
        XCTAssertEqual(results.myChangesRequested.count, 1)
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-shared")

        // Should NOT appear in needsReview (filtered out because reviewDecision == .changesRequested)
        XCTAssertEqual(results.needsReview.count, 0)
    }

    // MARK: API Error

    func testAPIErrorThrows() async throws {
        let errorJSON: [String: Any] = [
            "errors": [["message": "Bad credentials"]],
        ]
        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)

        MockURLProtocol.handlers = [
            { _ in (errorData, okResponse()) },
        ]

        let service = GitHubService(session: makeSession())
        do {
            _ = try await service.fetchAllPRs(token: "bad-token")
            XCTFail("Expected apiError to be thrown")
        } catch let error as GitHubService.GitHubError {
            if case let .apiError(message) = error {
                XCTAssertEqual(message, "Bad credentials")
            } else {
                XCTFail("Expected .apiError, got \(error)")
            }
        }
    }

    // MARK: Non-200 Status

    func testNon200StatusThrows() async throws {
        MockURLProtocol.handlers = [
            { _ in (Data(), errorResponse(statusCode: 403)) },
        ]

        let service = GitHubService(session: makeSession())
        do {
            _ = try await service.fetchAllPRs(token: "test-token")
            XCTFail("Expected invalidResponse to be thrown")
        } catch let error as GitHubService.GitHubError {
            if case let .invalidResponse(code) = error {
                XCTAssertEqual(code, 403)
            } else {
                XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: Needs Review Filters Out Approved/ChangesRequested

    func testNeedsReviewFiltersApprovedAndChangesRequested() async throws {
        let approvedPR = prNode(id: "pr-a", number: 30, title: "Approved review-requested", reviewDecision: "APPROVED")
        let changesPR = prNode(id: "pr-b", number: 31, title: "Changes review-requested", reviewDecision: "CHANGES_REQUESTED")
        let pendingPR = prNode(id: "pr-c", number: 32, title: "Pending review-requested")

        installHandlers(
            reviewRequested: [approvedPR, changesPR, pendingPR],
            authored: [],
            reviewed: []
        )

        let service = GitHubService(session: makeSession())
        let results = try await service.fetchAllPRs(token: "test-token")

        // Only the pending PR should be in needsReview
        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview.first?.id, "pr-c")

        // The changes_requested one should appear in myChangesRequested
        XCTAssertEqual(results.myChangesRequested.count, 1)
        XCTAssertEqual(results.myChangesRequested.first?.id, "pr-b")
    }
}
