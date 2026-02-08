@testable import PRMonitor
@preconcurrency import XCTest

// MARK: - Helpers

private func makePR(
    id: String,
    number: Int = 1,
    title: String = "Test PR"
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
        updatedAt: Date(),
        isDraft: false,
        reviewDecision: nil,
        additions: 0,
        deletions: 0,
        changedFiles: 0,
        totalComments: 0,
        reviewers: []
    )
}

// MARK: - Tests

@MainActor
final class SnoozeManagerTests: XCTestCase {
    private let testDefaultsKey = "snoozedPRs"
    private var manager: SnoozeManager!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        manager = SnoozeManager()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        manager = nil
        try await super.tearDown()
    }

    // MARK: snooze

    func testSnoozeAddsPR() {
        let pr = makePR(id: "pr-1", title: "Alpha PR")
        manager.snooze(pr, duration: .oneDay)

        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.prID, "pr-1")
        XCTAssertEqual(manager.entries.first?.prTitle, "Alpha PR")
        XCTAssertEqual(manager.entries.first?.duration, .oneDay)
    }

    func testSnoozedIDsContainsSnooze() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneWeek)

        XCTAssertTrue(manager.snoozedIDs.contains("pr-1"))
    }

    // MARK: unsnooze

    func testUnsnoozeRemovesPR() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneDay)
        XCTAssertEqual(manager.entries.count, 1)

        manager.unsnooze(prID: "pr-1")
        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertFalse(manager.snoozedIDs.contains("pr-1"))
    }

    func testUnsnoozeNonexistentIDIsNoOp() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneDay)

        manager.unsnooze(prID: "does-not-exist")
        XCTAssertEqual(manager.entries.count, 1)
    }

    // MARK: re-snooze replaces

    func testReSnoozeReplacesEntry() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneDay)
        manager.snooze(pr, duration: .oneMonth)

        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.duration, .oneMonth)
    }

    // MARK: cleanExpired

    func testCleanExpiredRemovesExpired() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneDay)

        // Manually replace with an already-expired entry
        let expired = SnoozeEntry(
            prID: "pr-1",
            prTitle: "Test PR",
            prRepository: "owner/repo",
            prNumber: 1,
            // swiftformat:disable:next noForceUnwrapInTests
            prURL: URL(string: "https://github.com/owner/repo/pull/1")!,
            snoozedAt: Date().addingTimeInterval(-90000), // > 1 day ago
            duration: .oneDay
        )
        // Replace via unsnooze + manually set
        manager.unsnooze(prID: "pr-1")

        // Add an active and an expired entry
        let activePR = makePR(id: "pr-2", title: "Active PR")
        manager.snooze(activePR, duration: .oneWeek)

        // We need to inject the expired entry directly for testing
        // Use persistence round-trip
        let entries = [expired, manager.entries.first].compactMap(\.self)
        let data = try? JSONEncoder().encode(entries)
        UserDefaults.standard.set(data, forKey: testDefaultsKey)

        // Re-create manager to pick up persisted data
        manager = SnoozeManager()
        XCTAssertEqual(manager.entries.count, 2)

        manager.cleanExpired()
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.prID, "pr-2")
    }

    func testCleanExpiredKeepsActiveEntries() {
        let pr = makePR(id: "pr-1")
        manager.snooze(pr, duration: .oneMonth)

        manager.cleanExpired()
        XCTAssertEqual(manager.entries.count, 1)
    }

    // MARK: sortedEntries

    func testSortedEntriesAlphabetical() {
        manager.snooze(makePR(id: "pr-1", title: "Zulu"), duration: .oneDay)
        manager.snooze(makePR(id: "pr-2", title: "Alpha"), duration: .oneDay)
        manager.snooze(makePR(id: "pr-3", title: "Mike"), duration: .oneDay)

        let titles = manager.sortedEntries.map(\.prTitle)
        XCTAssertEqual(titles, ["Alpha", "Mike", "Zulu"])
    }

    // MARK: persistence

    func testPersistenceRoundTrip() {
        let pr = makePR(id: "pr-1", title: "Persisted PR")
        manager.snooze(pr, duration: .oneWeek)

        // Create a new manager that should load from UserDefaults
        let newManager = SnoozeManager()
        XCTAssertEqual(newManager.entries.count, 1)
        XCTAssertEqual(newManager.entries.first?.prID, "pr-1")
        XCTAssertEqual(newManager.entries.first?.prTitle, "Persisted PR")
        XCTAssertEqual(newManager.entries.first?.duration, .oneWeek)
    }

    // MARK: SnoozeEntry computed properties

    func testSnoozeEntryExpiresAt() {
        let now = Date()
        let entry = SnoozeEntry(
            prID: "pr-1",
            prTitle: "Test",
            prRepository: "owner/repo",
            prNumber: 1,
            // swiftformat:disable:next noForceUnwrapInTests
            prURL: URL(string: "https://github.com/owner/repo/pull/1")!,
            snoozedAt: now,
            duration: .oneDay
        )
        XCTAssertEqual(entry.expiresAt.timeIntervalSince1970, now.addingTimeInterval(86400).timeIntervalSince1970, accuracy: 1)
    }

    func testSnoozeEntryIsExpired() {
        let pastEntry = SnoozeEntry(
            prID: "pr-1",
            prTitle: "Test",
            prRepository: "owner/repo",
            prNumber: 1,
            // swiftformat:disable:next noForceUnwrapInTests
            prURL: URL(string: "https://github.com/owner/repo/pull/1")!,
            snoozedAt: Date().addingTimeInterval(-90000),
            duration: .oneDay
        )
        XCTAssertTrue(pastEntry.isExpired)

        let futureEntry = SnoozeEntry(
            prID: "pr-2",
            prTitle: "Test",
            prRepository: "owner/repo",
            prNumber: 2,
            // swiftformat:disable:next noForceUnwrapInTests
            prURL: URL(string: "https://github.com/owner/repo/pull/2")!,
            snoozedAt: Date(),
            duration: .oneMonth
        )
        XCTAssertFalse(futureEntry.isExpired)
    }
}
