import Foundation

protocol GitHubServiceProtocol: Sendable {
    func fetchAllPRs() async throws -> PRFetchResults
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
        async let needsReview = fetchPRs(query: "is:pr is:open review-requested:@me", token: token)
        async let authored = fetchPRs(query: "is:pr is:open author:@me", token: token)
        // PRs I've reviewed that aren't approved (includes changes_requested and pending)
        async let reviewed = fetchPRs(query: "is:pr is:open -is:draft reviewed-by:@me -author:@me -review:approved", token: token)

        let (reviewPRs, authoredPRs, reviewedPRs) = try await (needsReview, authored, reviewed)

        var results = PRFetchResults()

        // PRs where I'm requested to review (exclude approved and changes_requested)
        results.needsReview = reviewPRs.filter { pr in
            pr.reviewDecision != .approved && pr.reviewDecision != .changesRequested
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
        let requestedWithChanges = reviewPRs.filter { $0.reviewDecision == .changesRequested }

        // Combine and dedupe by ID
        var seen = Set<String>()
        var combined: [PullRequest] = []
        for pr in reviewedPRs + requestedWithChanges {
            if !seen.contains(pr.id) {
                seen.insert(pr.id)
                combined.append(pr)
            }
        }
        results.myChangesRequested = combined

        return results
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
                author {
                  login
                  avatarUrl(size: 64)
                }
                repository {
                  nameWithOwner
                }
                reviewDecision
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

        return result.data?.search.nodes.compactMap { node -> PullRequest? in
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

            return PullRequest(
                id: id,
                number: number,
                title: title,
                url: url,
                repository: repository,
                author: author,
                authorAvatarURL: authorAvatarURL,
                createdAt: createdAt,
                isDraft: node.isDraft ?? false,
                reviewDecision: reviewDecision
            )
        } ?? []
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
    let author: Author?
    let repository: Repository?
    let reviewDecision: String?
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
