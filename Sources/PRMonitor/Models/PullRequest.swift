import Foundation

struct Reviewer: Codable, Hashable {
    enum Kind: String, Codable {
        case user
        case team
    }

    let kind: Kind
    let id: String
    let displayName: String
    let avatarURL: URL?
}

struct PullRequest: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let authorAvatarURL: URL?
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: ReviewDecision?
    let viewerDidApprove: Bool
    let hasAnyApproval: Bool
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let totalComments: Int
    let reviewers: [Reviewer]
    let viewerDidReview: Bool
    let isDirectReviewRequested: Bool
    let requestedTeamKeys: Set<String>

    init(
        id: String,
        number: Int,
        title: String,
        url: URL,
        repository: String,
        author: String,
        authorAvatarURL: URL?,
        createdAt: Date,
        updatedAt: Date,
        isDraft: Bool,
        reviewDecision: ReviewDecision?,
        viewerDidApprove: Bool,
        hasAnyApproval: Bool,
        additions: Int,
        deletions: Int,
        changedFiles: Int,
        totalComments: Int,
        reviewers: [Reviewer],
        viewerDidReview: Bool = false,
        isDirectReviewRequested: Bool = false,
        requestedTeamKeys: Set<String> = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.viewerDidApprove = viewerDidApprove
        self.hasAnyApproval = hasAnyApproval
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.totalComments = totalComments
        self.reviewers = reviewers
        self.viewerDidReview = viewerDidReview
        self.isDirectReviewRequested = isDirectReviewRequested
        self.requestedTeamKeys = requestedTeamKeys
    }

    enum ReviewDecision: String, Codable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
    }
}

struct PRFetchResults {
    var needsReview: [PullRequest] = []
    var waitingForReviewers: [PullRequest] = []
    var approved: [PullRequest] = []
    var changesRequested: [PullRequest] = []
    var myChangesRequested: [PullRequest] = []
    var drafts: [PullRequest] = []
}
