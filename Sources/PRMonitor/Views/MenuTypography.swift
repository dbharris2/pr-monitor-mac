import SwiftUI

extension EnvironmentValues {
    @Entry var menuFontScale: CGFloat = 1
}

enum MenuFontStyle {
    case body
    case caption
    case caption2
    case headline

    var size: CGFloat {
        switch self {
        case .body: 13
        case .caption: 11
        case .caption2: 10
        case .headline: 17
        }
    }

    var weight: Font.Weight {
        switch self {
        case .body, .caption, .caption2: .regular
        case .headline: .semibold
        }
    }
}

private struct MenuScaledFont: ViewModifier {
    @Environment(\.menuFontScale) private var scale
    let style: MenuFontStyle

    func body(content: Content) -> some View {
        content.font(.system(size: style.size * scale, weight: style.weight))
    }
}

extension View {
    func menuFont(_ style: MenuFontStyle) -> some View {
        modifier(MenuScaledFont(style: style))
    }
}
