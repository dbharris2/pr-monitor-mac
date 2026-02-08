import Foundation

@MainActor
class SnoozeManager: ObservableObject {
    @Published private(set) var entries: [SnoozeEntry] = []

    private let userDefaultsKey = "snoozedPRs"

    var snoozedIDs: Set<String> {
        Set(entries.map(\.prID))
    }

    var sortedEntries: [SnoozeEntry] {
        entries.sorted { $0.prTitle.localizedCaseInsensitiveCompare($1.prTitle) == .orderedAscending }
    }

    init() {
        load()
    }

    func snooze(_ pr: PullRequest, duration: SnoozeDuration) {
        entries.removeAll { $0.prID == pr.id }
        let entry = SnoozeEntry(
            prID: pr.id,
            prTitle: pr.title,
            prRepository: pr.repository,
            prNumber: pr.number,
            prURL: pr.url,
            snoozedAt: Date(),
            duration: duration
        )
        entries.append(entry)
        save()
    }

    func unsnooze(prID: String) {
        entries.removeAll { $0.prID == prID }
        save()
    }

    func cleanExpired() {
        let before = entries.count
        entries.removeAll { $0.isExpired }
        if entries.count != before {
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([SnoozeEntry].self, from: data) else { return }
        entries = decoded
    }
}
