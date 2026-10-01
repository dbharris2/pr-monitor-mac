import Foundation

struct ReviewerGroup: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let usernames: [String]

    init(id: String = UUID().uuidString, name: String, usernames: [String]) {
        self.id = id
        self.name = name
        self.usernames = usernames
    }
}
