import SwiftUI

enum MenuSizePreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    var width: CGFloat {
        switch self {
        case .compact: 340
        case .standard: 380
        case .large: 440
        }
    }
}

enum FontSizePreset: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .standard: 1
        case .large: 1.2
        }
    }
}
