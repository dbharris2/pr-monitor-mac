struct MenuPRSections {
    static let maxExpandedRowsWithoutScrolling = 7

    let needsReviewCount: Int
    let changesRequestedCount: Int
    let approvedCount: Int
    let waitingForReviewersCount: Int
    let myChangesRequestedCount: Int
    let draftsCount: Int
    let snoozedCount: Int
    let expandedSections: [String: Bool]

    var visibleExpandedPRCount: Int {
        var count = 0
        if isExpanded("needsReview") { count += needsReviewCount }
        if isExpanded("changesRequested") { count += changesRequestedCount }
        if isExpanded("approved") { count += approvedCount }
        if isExpanded("waitingForReviewers") { count += waitingForReviewersCount }
        if isExpanded("myChangesRequested") { count += myChangesRequestedCount }
        if isExpanded("drafts") { count += draftsCount }
        if isExpanded("snoozed") { count += snoozedCount }
        return count
    }

    var shouldConstrainPRSections: Bool {
        visibleExpandedPRCount > Self.maxExpandedRowsWithoutScrolling
    }

    private func isExpanded(_ section: String) -> Bool {
        expandedSections[section] == true
    }
}
