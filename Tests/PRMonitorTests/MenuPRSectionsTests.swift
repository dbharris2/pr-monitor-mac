@testable import PRMonitor
import XCTest

final class MenuPRSectionsTests: XCTestCase {
    func testDoesNotConstrainAtThreshold() {
        let layout = makeLayout(needsReviewCount: MenuPRSections.maxExpandedRowsWithoutScrolling)

        XCTAssertEqual(layout.visibleExpandedPRCount, 7)
        XCTAssertFalse(layout.shouldConstrainPRSections)
    }

    func testConstrainsAboveThreshold() {
        let layout = makeLayout(needsReviewCount: MenuPRSections.maxExpandedRowsWithoutScrolling + 1)

        XCTAssertEqual(layout.visibleExpandedPRCount, 8)
        XCTAssertTrue(layout.shouldConstrainPRSections)
    }

    func testCollapsedSectionsDoNotContributeToVisibleCount() {
        let layout = makeLayout(
            needsReviewCount: 4,
            approvedCount: 20,
            expandedSections: [
                "needsReview": true,
                "approved": false,
            ]
        )

        XCTAssertEqual(layout.visibleExpandedPRCount, 4)
        XCTAssertFalse(layout.shouldConstrainPRSections)
    }

    func testSnoozedRowsOnlyContributeWhenExpanded() {
        let collapsed = makeLayout(
            needsReviewCount: 1,
            snoozedCount: 10,
            expandedSections: [
                "needsReview": true,
                "snoozed": false,
            ]
        )
        let expanded = makeLayout(
            needsReviewCount: 1,
            snoozedCount: 10,
            expandedSections: [
                "needsReview": true,
                "snoozed": true,
            ]
        )

        XCTAssertEqual(collapsed.visibleExpandedPRCount, 1)
        XCTAssertFalse(collapsed.shouldConstrainPRSections)
        XCTAssertEqual(expanded.visibleExpandedPRCount, 11)
        XCTAssertTrue(expanded.shouldConstrainPRSections)
    }

    private func makeLayout(
        needsReviewCount: Int = 0,
        changesRequestedCount: Int = 0,
        approvedCount: Int = 0,
        waitingForReviewersCount: Int = 0,
        myChangesRequestedCount: Int = 0,
        draftsCount: Int = 0,
        snoozedCount: Int = 0,
        expandedSections: [String: Bool] = [
            "needsReview": true,
            "changesRequested": true,
            "approved": true,
            "waitingForReviewers": true,
            "myChangesRequested": true,
            "drafts": true,
            "snoozed": true,
        ]
    ) -> MenuPRSections {
        MenuPRSections(
            needsReviewCount: needsReviewCount,
            changesRequestedCount: changesRequestedCount,
            approvedCount: approvedCount,
            waitingForReviewersCount: waitingForReviewersCount,
            myChangesRequestedCount: myChangesRequestedCount,
            draftsCount: draftsCount,
            snoozedCount: snoozedCount,
            expandedSections: expandedSections
        )
    }
}
