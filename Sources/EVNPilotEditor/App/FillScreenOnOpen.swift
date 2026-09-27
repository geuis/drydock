import AppKit
import SwiftUI

// Sizes the hosting window to the screen's usable area (below the menu bar,
// above the Dock) when it first opens - like the green button's "Fill", not
// full-screen mode. Done through the window itself because SwiftUI's
// window-placement API needs macOS 15 and this app supports macOS 14.
struct FillScreenOnOpen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        FillingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FillingView: NSView {
        private var hasFilled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard !hasFilled, let window else { return }

            hasFilled = true

            // Next run loop, so SwiftUI's own restored frame doesn't win.
            DispatchQueue.main.async {
                guard let screen = window.screen ?? NSScreen.main else { return }

                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }
}
