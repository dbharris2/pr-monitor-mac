import Foundation

struct PullRequest: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let authorAvatarURL: URL?
    let createdAt: Date
    let isDraft: Bool
    let reviewDecision: ReviewDecision?

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
