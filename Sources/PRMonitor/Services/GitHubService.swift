import Foundation

protocol GitHubServiceProtocol: Sendable {
    func fetchAllPRs() async throws -> PRFetchResults
    func fetchLatestRelease() async throws -> String?
}

actor GitHubService: GitHubServiceProtocol {
    private let gh: GHCommandProtocol

    init(gh: GHCommandProtocol = GHCommand.shared) {
        self.gh = gh
    }

    enum GitHubError: LocalizedError {
        case ghNotInstalled
        case ghNotAuthenticated
        case subprocessFailed(String)
        case apiError(String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .ghNotInstalled:
                "GitHub CLI not installed. Install with `brew install gh`, then sign in with `gh auth login`."
            case .ghNotAuthenticated:
                "Not signed in to GitHub. Run `gh auth login` in your terminal."
            case let .subprocessFailed(message):
                "GitHub CLI error: \(message)"
            case let .apiError(message):
                "GitHub API error: \(message)"
            case let .decodingError(message):
                "Failed to parse response: \(message)"
            }
        }
    }

    func fetchAllPRs() async throws -> PRFetchResults {
        async let needsReview = fetchPRs(query: "is:pr is:open -is:draft review-requested:@me")
        async let authored = fetchPRs(query: "is:pr is:open author:@me")
        // Every PR I've reviewed (any state — comment, changes-requested, approved).
        async let reviewed = fetchPRs(query: "is:pr is:open -is:draft reviewed-by:@me -author:@me", viewerReviewed: true)

        let (reviewResult, authoredResult, reviewedResult) = try await (needsReview, authored, reviewed)
        let reviewPRs = reviewResult.prs
        let authoredPRs = authoredResult.prs
        let reviewedPRs = reviewedResult.prs

        var results = PRFetchResults()

        // PRs where I'm requested to review. Drop ones already approved or with changes requested.
        // hasAnyApproval is the fallback for repos without branch protection — reviewDecision stays
        // empty there even after someone approves, so we'd otherwise nag every requested reviewer
        // on PRs that already have a green check.
        results.needsReview = reviewPRs.filter { pr in
            pr.reviewDecision != .approved
                && pr.reviewDecision != .changesRequested
                && !pr.hasAnyApproval
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

        // "Reviewed" section: any PR with a state-changing review (approval or changes-requested)
        // OR any PR I've reviewed myself (in any way). PRs where I'm requested but only have
        // comment-level reviews (state unchanged) stay in "Needs my review" — same model as sam.
        let needsReviewIDs = Set(results.needsReview.map(\.id))
        let requestedWithStateChange = reviewPRs.filter { pr in
            pr.reviewDecision == .approved
                || pr.reviewDecision == .changesRequested
                || pr.hasAnyApproval
        }

        var seen = Set<String>()
        var combined: [PullRequest] = []
        for pr in reviewedPRs + requestedWithStateChange
            where seen.insert(pr.id).inserted && !needsReviewIDs.contains(pr.id) {
            combined.append(pr)
        }
        results.myChangesRequested = combined

        return results
    }

    func fetchLatestRelease() async throws -> String? {
        do {
            let stdout = try await gh.runExpectingSuccess(
                arguments: ["api", "/repos/dbharris2/pr-monitor-mac/releases/latest"],
                stdin: nil,
                timeout: 15
            )
            let json = try JSONSerialization.jsonObject(with: stdout) as? [String: Any]
            guard let tagName = json?["tag_name"] as? String else { return nil }
            return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        } catch {
            // 404 (no releases) and any other failure: best-effort, return nil
            return nil
        }
    }

    private func fetchPRs(query: String, viewerReviewed: Bool = false) async throws -> (viewerLogin: String, prs: [PullRequest]) {
        let graphQLQuery = """
        {
          viewer { login }
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
                reviewRequests(first: 100) {
                  nodes {
                    requestedReviewer {
                      __typename
                      ... on Team {
                        id
                        organization { login }
                      }
                      ... on User {
                        login
                        avatarUrl(size: 64)
                      }
                      ... on Team {
                        slug
                        name
                        avatarUrl(size: 64)
                      }
                    }
                  }
                }
                latestReviews(first: 5) {
                  nodes {
                    state
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

        // -F (field) supports `@-` to read the value from stdin. -f (raw-field) does NOT — it would send
        // the literal string "@-" as the query, which GitHub's GraphQL parser rejects.
        let stdinPayload = Data(graphQLQuery.utf8)
        let data: Data
        do {
            data = try await gh.runExpectingSuccess(
                arguments: ["api", "graphql", "-F", "query=@-"],
                stdin: stdinPayload,
                timeout: 30
            )
        } catch let error as GHCommand.GHError {
            throw Self.mapGHError(error)
        }

        let result: GraphQLResponse
        do {
            result = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch {
            throw GitHubError.decodingError(error.localizedDescription)
        }

        if let errors = result.errors, !errors.isEmpty {
            throw GitHubError.apiError(errors.first?.message ?? "Unknown error")
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let viewerLogin = result.data?.viewer?.login ?? ""
        let prs = result.data?.search.nodes.compactMap { node in
            Self.makePullRequest(
                from: node,
                viewerLogin: viewerLogin,
                viewerReviewed: viewerReviewed,
                dateFormatter: dateFormatter
            )
        } ?? []
        return (viewerLogin, prs)
    }

    private static func mapGHError(_ error: GHCommand.GHError) -> GitHubError {
        switch error {
        case .ghNotFound:
            .ghNotInstalled
        case let .nonZeroExit(_, stderr):
            stderr.lowercased().contains("authentication") || stderr.lowercased().contains("not logged")
                ? .ghNotAuthenticated
                : .subprocessFailed(stderr.isEmpty ? "Unknown error" : stderr)
        case let .timeout(seconds):
            .subprocessFailed("Timed out after \(Int(seconds))s")
        case let .launchFailed(message):
            .subprocessFailed(message)
        }
    }

    private static func makePullRequest(
        from node: PRNode,
        viewerLogin: String,
        viewerReviewed: Bool = false,
        dateFormatter: ISO8601DateFormatter
    ) -> PullRequest? {
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
        let requestedReviewers = node.reviewRequests?.nodes.compactMap(\.requestedReviewer) ?? []
        let isDirectReviewRequested = requestedReviewers.contains { $0.login == viewerLogin }
        let requestedTeamKeys = Set(requestedReviewers.compactMap(Self.teamKey(from:)))

        let viewerDidApprove = !viewerLogin.isEmpty && (node.latestReviews?.nodes ?? []).contains {
            $0.author?.login == viewerLogin && $0.state == "APPROVED"
        }
        let hasAnyApproval = (node.latestReviews?.nodes ?? []).contains { $0.state == "APPROVED" }

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
            viewerDidApprove: viewerDidApprove,
            hasAnyApproval: hasAnyApproval,
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0,
            totalComments: node.totalCommentsCount ?? 0,
            reviewers: reviewers,
            viewerDidReview: viewerReviewed,
            isDirectReviewRequested: isDirectReviewRequested,
            requestedTeamKeys: requestedTeamKeys
        )
    }

    private static func mergeReviewers(from node: PRNode) -> [Reviewer] {
        var seenIDs = Set<String>()
        var reviewers: [Reviewer] = []
        for reqNode in node.reviewRequests?.nodes ?? [] {
            guard let requested = reqNode.requestedReviewer,
                  let reviewer = Self.makeReviewer(from: requested),
                  seenIDs.insert("\(reviewer.kind.rawValue):\(reviewer.id)").inserted else { continue }
            reviewers.append(reviewer)
        }
        for revNode in node.latestReviews?.nodes ?? [] {
            guard let login = revNode.author?.login,
                  seenIDs.insert("user:\(login)").inserted else { continue }
            reviewers.append(Reviewer(
                kind: .user,
                id: login,
                displayName: login,
                avatarURL: revNode.author?.avatarUrl.flatMap(URL.init(string:))
            ))
        }
        return reviewers
    }

    private static func makeReviewer(from requested: RequestedReviewer) -> Reviewer? {
        let avatarURL = requested.avatarUrl.flatMap(URL.init(string:))
        if let login = requested.login {
            return Reviewer(kind: .user, id: login, displayName: login, avatarURL: avatarURL)
        }
        if let slug = requested.slug {
            return Reviewer(
                kind: .team,
                id: slug,
                displayName: requested.name ?? slug,
                avatarURL: avatarURL
            )
        }
        return nil
    }

    private static func teamKey(from requested: RequestedReviewer) -> String? {
        guard let slug = requested.slug else { return nil }
        guard let organization = requested.organization?.login, !organization.isEmpty else { return slug }
        return "\(organization)/\(slug)"
    }
}

// MARK: - GraphQL Response Types

private struct GraphQLResponse: Codable {
    let data: ResponseData?
    let errors: [GraphQLError]?
}

private struct ResponseData: Codable {
    let viewer: Viewer?
    let search: SearchResult
}

private struct Viewer: Codable {
    let login: String
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
    let id: String?
    let login: String?
    let slug: String?
    let name: String?
    let avatarUrl: String?
    let organization: TeamOrganization?
}

private struct TeamOrganization: Codable {
    let login: String
}

private struct LatestReviewConnection: Codable {
    let nodes: [LatestReviewNode]
}

private struct LatestReviewNode: Codable {
    let state: String?
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
