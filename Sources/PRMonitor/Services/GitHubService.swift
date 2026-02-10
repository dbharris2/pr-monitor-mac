import Foundation

protocol GitHubServiceProtocol: Sendable {
    func fetchAllPRs() async throws -> PRFetchResults
    func fetchLatestRelease() async throws -> String?
}

actor GitHubService: GitHubServiceProtocol {
    private let baseURL = URL(string: "https://api.github.com/graphql")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum GitHubError: LocalizedError {
        case noToken
        case invalidResponse(Int)
        case apiError(String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                "No GitHub token configured. Add your token in Settings."
            case let .invalidResponse(statusCode):
                "GitHub API returned status \(statusCode)"
            case let .apiError(message):
                "GitHub API error: \(message)"
            case let .decodingError(message):
                "Failed to parse response: \(message)"
            }
        }
    }

    func fetchAllPRs() async throws -> PRFetchResults {
        guard let token = Keychain.getToken() else {
            throw GitHubError.noToken
        }
        return try await fetchAllPRs(token: token)
    }

    func fetchAllPRs(token: String) async throws -> PRFetchResults {
        async let needsReview = fetchPRs(query: "is:pr is:open -is:draft review-requested:@me", token: token)
        async let authored = fetchPRs(query: "is:pr is:open author:@me", token: token)
        // PRs I've reviewed that aren't approved (includes changes_requested and pending)
        async let reviewed = fetchPRs(query: "is:pr is:open -is:draft reviewed-by:@me -author:@me -review:approved", token: token)

        let (reviewPRs, authoredPRs, reviewedPRs) = try await (needsReview, authored, reviewed)

        var results = PRFetchResults()

        // PRs where I'm requested to review (exclude drafts, approved, and changes_requested)
        results.needsReview = reviewPRs.filter { pr in
            !pr.isDraft && pr.reviewDecision != .approved && pr.reviewDecision != .changesRequested
        }

        // PRs I authored
        for pr in authoredPRs {
            if pr.isDraft {
                results.drafts.append(pr)
            } else if pr.reviewDecision == .approved {
                results.approved.append(pr)
            } else if pr.reviewDecision == .changesRequested {
                results.changesRequested.append(pr)
            } else {
                results.waitingForReviewers.append(pr)
            }
        }

        // "Reviewed" section: PRs I've reviewed OR PRs where I'm requested but has changes_requested
        // Exclude PRs already in "Needs my review" (re-requested after previous review)
        let needsReviewIDs = Set(results.needsReview.map(\.id))
        let requestedWithChanges = reviewPRs.filter { $0.reviewDecision == .changesRequested }

        // Combine and dedupe by ID, excluding PRs that need my review
        var seen = Set<String>()
        var combined: [PullRequest] = []
        for pr in reviewedPRs + requestedWithChanges
            where seen.insert(pr.id).inserted && !needsReviewIDs.contains(pr.id) {
            combined.append(pr)
        }
        results.myChangesRequested = combined

        return results
    }

    func fetchLatestRelease() async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/dbharris2/pr-monitor-mac/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        // 404 means no releases exist
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tagName = json?["tag_name"] as? String else {
            return nil
        }

        // Strip leading "v" if present
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private func fetchPRs(query: String, token: String) async throws -> [PullRequest] {
        let graphQLQuery = """
        {
          search(query: "\(query)", type: ISSUE, first: 50) {
            nodes {
              ... on PullRequest {
                id
                number
                title
                url
                isDraft
                createdAt
                updatedAt
                author {
                  login
                  avatarUrl(size: 64)
                }
                repository {
                  nameWithOwner
                }
                reviewDecision
                additions
                deletions
                changedFiles
                totalCommentsCount
                reviewRequests(first: 5) {
                  nodes {
                    requestedReviewer {
                      ... on User {
                        login
                        avatarUrl(size: 64)
                      }
                    }
                  }
                }
                latestReviews(first: 5) {
                  nodes {
                    author {
                      login
                      avatarUrl(size: 64)
                    }
                  }
                }
              }
            }
          }
        }
        """

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["query": graphQLQuery]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.invalidResponse(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(GraphQLResponse.self, from: data)

        if let errors = result.errors, !errors.isEmpty {
            throw GitHubError.apiError(errors.first?.message ?? "Unknown error")
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        return result.data?.search.nodes.compactMap { node in
            Self.makePullRequest(from: node, dateFormatter: dateFormatter)
        } ?? []
    }

    private static func makePullRequest(from node: PRNode, dateFormatter: ISO8601DateFormatter) -> PullRequest? {
        guard let id = node.id,
              let number = node.number,
              let title = node.title,
              let urlString = node.url,
              let url = URL(string: urlString),
              let repository = node.repository?.nameWithOwner,
              let author = node.author?.login,
              let createdAtString = node.createdAt,
              let createdAt = dateFormatter.date(from: createdAtString) else {
            return nil
        }

        let updatedAt: Date = if let updatedAtString = node.updatedAt,
                                 let parsed = dateFormatter.date(from: updatedAtString) {
            parsed
        } else {
            createdAt
        }

        let reviewDecision: PullRequest.ReviewDecision? = if let decision = node.reviewDecision {
            PullRequest.ReviewDecision(rawValue: decision)
        } else {
            nil
        }

        let authorAvatarURL: URL? = if let avatarUrlString = node.author?.avatarUrl {
            URL(string: avatarUrlString)
        } else {
            nil
        }

        let reviewers = Self.mergeReviewers(from: node)

        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            repository: repository,
            author: author,
            authorAvatarURL: authorAvatarURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDraft: node.isDraft ?? false,
            reviewDecision: reviewDecision,
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0,
            totalComments: node.totalCommentsCount ?? 0,
            reviewers: reviewers
        )
    }

    private static func mergeReviewers(from node: PRNode) -> [Reviewer] {
        var seenLogins = Set<String>()
        var reviewers: [Reviewer] = []
        for reqNode in node.reviewRequests?.nodes ?? [] {
            guard let login = reqNode.requestedReviewer?.login, seenLogins.insert(login).inserted else { continue }
            reviewers.append(Reviewer(login: login, avatarURL: reqNode.requestedReviewer?.avatarUrl.flatMap(URL.init(string:))))
        }
        for revNode in node.latestReviews?.nodes ?? [] {
            guard let login = revNode.author?.login, seenLogins.insert(login).inserted else { continue }
            reviewers.append(Reviewer(login: login, avatarURL: revNode.author?.avatarUrl.flatMap(URL.init(string:))))
        }
        return reviewers
    }
}

// MARK: - GraphQL Response Types

private struct GraphQLResponse: Codable {
    let data: ResponseData?
    let errors: [GraphQLError]?
}

private struct ResponseData: Codable {
    let search: SearchResult
}

private struct SearchResult: Codable {
    let nodes: [PRNode]
}

private struct PRNode: Codable {
    let id: String?
    let number: Int?
    let title: String?
    let url: String?
    let isDraft: Bool?
    let createdAt: String?
    let updatedAt: String?
    let author: Author?
    let repository: Repository?
    let reviewDecision: String?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let totalCommentsCount: Int?
    let reviewRequests: ReviewRequestConnection?
    let latestReviews: LatestReviewConnection?
}

private struct ReviewRequestConnection: Codable {
    let nodes: [ReviewRequestNode]
}

private struct ReviewRequestNode: Codable {
    let requestedReviewer: RequestedReviewer?
}

private struct RequestedReviewer: Codable {
    let login: String?
    let avatarUrl: String?
}

private struct LatestReviewConnection: Codable {
    let nodes: [LatestReviewNode]
}

private struct LatestReviewNode: Codable {
    let author: Author?
}

private struct Author: Codable {
    let login: String
    let avatarUrl: String?
}

private struct Repository: Codable {
    let nameWithOwner: String
}

private struct GraphQLError: Codable {
    let message: String
}
