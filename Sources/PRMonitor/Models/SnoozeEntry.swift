import Foundation

enum SnoozeDuration: String, Codable, CaseIterable {
    case oneDay
    case oneWeek
    case oneMonth

    var timeInterval: TimeInterval {
        switch self {
        case .oneDay: 86400
        case .oneWeek: 604_800
        case .oneMonth: 2_592_000 // 30 days
        }
    }

    var displayName: String {
        switch self {
        case .oneDay: "1 Day"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        }
    }
}

struct SnoozeEntry: Codable, Identifiable {
    var id: String {
        prID
    }

    let prID: String
    let prTitle: String
    let prRepository: String
    let prNumber: Int
    let prURL: URL
    let snoozedAt: Date
    let duration: SnoozeDuration

    var expiresAt: Date {
        snoozedAt.addingTimeInterval(duration.timeInterval)
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }
}
