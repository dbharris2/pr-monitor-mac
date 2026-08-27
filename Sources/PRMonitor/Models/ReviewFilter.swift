import Foundation

struct ReviewFilterAuthor: Codable, Equatable, Hashable, Identifiable {
    var username: String
    var isIncluded: Bool

    var id: String {
        username.lowercased()
    }
}

struct ReviewFilterRepository: Codable, Equatable, Hashable, Identifiable {
    var repository: String
    var isIncluded: Bool

    var id: String {
        repository.lowercased()
    }
}

struct ReviewFilterTeam: Codable, Equatable, Hashable, Identifiable {
    var team: String
    var isIncluded: Bool

    var id: String {
        team.lowercased()
    }
}

struct ReviewFilter: Codable, Equatable, Identifiable {
    static let allID = "all"

    let id: String
    var name: String
    var includesDirectRequests: Bool
    var teams: [ReviewFilterTeam]
    var authors: [ReviewFilterAuthor]
    var repositories: [ReviewFilterRepository]

    init(
        id: String,
        name: String,
        includesDirectRequests: Bool,
        teams: [ReviewFilterTeam] = [],
        authors: [ReviewFilterAuthor] = [],
        repositories: [ReviewFilterRepository] = []
    ) {
        self.id = id
        self.name = name
        self.includesDirectRequests = includesDirectRequests
        self.teams = teams
        self.authors = authors
        self.repositories = repositories
    }

    static let all = ReviewFilter(
        id: allID,
        name: "All",
        includesDirectRequests: true,
        teams: [],
        authors: []
    )

    var isAll: Bool {
        id == Self.allID
    }
}

struct ReviewFilterCounts {
    let needsReview: Int
    let approved: Int
    let changesRequested: Int
}
