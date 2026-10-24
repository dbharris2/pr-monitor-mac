import Foundation

enum RepositoryDisplayStyle: String, CaseIterable, Identifiable {
    case organizationAndName
    case nameOnly

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .organizationAndName: "Org/repo"
        case .nameOnly: "Repo name"
        }
    }

    func displayName(for repository: String) -> String {
        switch self {
        case .organizationAndName:
            repository
        case .nameOnly:
            repository.split(separator: "/").last.map(String.init) ?? repository
        }
    }
}
