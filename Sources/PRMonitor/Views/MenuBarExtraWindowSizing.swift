import AppKit
import MenuBarExtraAccess
import SwiftUI

extension View {
    func fitMenuBarExtraWindow(configure: @escaping (NSWindow) -> Void) -> some View {
        modifier(MenuBarExtraWindowSizing(configure: configure))
    }
}

private struct MenuBarExtraWindowSizing: ViewModifier {
    let configure: (NSWindow) -> Void

    @State private var window: NSWindow?
    @State private var contentSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MenuBarExtraContentSizeKey.self,
                        value: proxy.size
                    )
                }
            )
            .onPreferenceChange(MenuBarExtraContentSizeKey.self) { size in
                contentSize = size
                resizeWindow(window, toContentSize: size)
            }
            .introspectMenuBarExtraWindow { window in
                self.window = window
                configure(window)
                resizeWindow(window, toContentSize: contentSize)
            }
    }

    private func resizeWindow(_ window: NSWindow?, toContentSize contentSize: CGSize) {
        guard let window,
              contentSize.width > 0,
              contentSize.height > 0 else {
            return
        }

        DispatchQueue.main.async {
            Self.resize(window, toContentSize: contentSize)
        }
    }

    @MainActor
    private static func resize(_ window: NSWindow, toContentSize contentSize: CGSize) {
        let targetContentSize = NSSize(
            width: ceil(contentSize.width),
            height: ceil(contentSize.height)
        )
        let currentContentSize = window.contentView?.bounds.size ?? .zero

        guard abs(currentContentSize.width - targetContentSize.width) > 0.5
            || abs(currentContentSize.height - targetContentSize.height) > 0.5 else {
            return
        }

        window.minSize = NSSize(width: 1, height: 1)
        window.contentMinSize = NSSize(width: 1, height: 1)

        let currentFrame = window.frame
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
        var targetFrame = currentFrame
        targetFrame.size = targetFrameSize
        targetFrame.origin.y = currentFrame.maxY - targetFrameSize.height

        window.setFrame(targetFrame, display: true)
    }
}

private struct MenuBarExtraContentSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
