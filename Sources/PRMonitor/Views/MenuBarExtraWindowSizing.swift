import AppKit
import SwiftUI

extension View {
    func fitMenuBarExtraWindow(
        configure: @escaping (NSWindow) -> Void,
        onVisibleScreenHeightChange: @escaping (CGFloat) -> Void
    ) -> some View {
        let fitter = MenuBarExtraWindowFitter(
            configure: configure,
            onVisibleScreenHeightChange: onVisibleScreenHeightChange
        )
        return background(fitter.frame(width: 0, height: 0))
    }
}

private struct MenuBarExtraWindowFitter: NSViewRepresentable {
    let configure: (NSWindow) -> Void
    let onVisibleScreenHeightChange: (CGFloat) -> Void

    func makeNSView(context _: Context) -> FittingView {
        let view = FittingView()
        view.configureWindow = configure
        view.onVisibleScreenHeightChange = onVisibleScreenHeightChange
        return view
    }

    func updateNSView(_ nsView: FittingView, context _: Context) {
        nsView.configureWindow = configure
        nsView.onVisibleScreenHeightChange = onVisibleScreenHeightChange
        nsView.scheduleFit()
    }

    final class FittingView: NSView {
        var configureWindow: ((NSWindow) -> Void)?
        var onVisibleScreenHeightChange: ((CGFloat) -> Void)?

        override var intrinsicContentSize: NSSize {
            NSSize(width: 0, height: 0)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleFit()
        }

        func scheduleFit() {
            DispatchQueue.main.async { [weak self] in
                self?.fitWindowToHostedContent()
            }
        }

        private func fitWindowToHostedContent() {
            guard let window,
                  let contentView = window.contentView else {
                return
            }

            configureWindow?(window)
            if let visibleScreenHeight = window.screen?.visibleFrame.height {
                onVisibleScreenHeightChange?(visibleScreenHeight)
            }
            contentView.layoutSubtreeIfNeeded()

            let targetContentSize = contentView.fittingSize
            guard targetContentSize.width > 0,
                  targetContentSize.height > 0 else {
                return
            }

            Self.resize(window, toContentSize: targetContentSize)
        }

        @MainActor
        private static func resize(_ window: NSWindow, toContentSize contentSize: NSSize) {
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
}
