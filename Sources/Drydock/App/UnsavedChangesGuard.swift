import AppKit
import SwiftUI

// Whether one window's open pilot has unsaved edits. Every tracker is also
// listed app-wide, so quitting can check all windows at once.
@MainActor
final class UnsavedChangesTracker: ObservableObject {
    private static let trackers: NSHashTable<UnsavedChangesTracker> = .weakObjects()

    var hasUnsavedChanges: Bool = false

    init() {
        Self.trackers.add(self)
    }

    static var anyHaveUnsavedChanges: Bool {
        trackers.allObjects.contains { $0.hasUnsavedChanges }
    }
}

// One wording for "you'd lose your edits", shared by quit and window close.
@MainActor
enum UnsavedChangesAlert {
    // True when the user chose to throw the edits away.
    static func confirmDiscard(actionTitle: String) -> Bool {
        let alert: NSAlert = NSAlert()
        alert.messageText = "Discard unsaved pilot changes?"
        alert.informativeText = "Your edits haven't been written to the pilot file. Use \"Save Pilot Changes\" first to keep them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")

        let discardButton: NSButton = alert.addButton(withTitle: actionTitle)
        discardButton.hasDestructiveAction = true

        return alert.runModal() == .alertSecondButtonReturn
    }
}

// Asks before quitting throws away unsaved edits in any window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppSettings.storedChecksForUpdatesAutomatically else { return }

        UpdateChecker.shared.checkAutomatically()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UnsavedChangesTracker.anyHaveUnsavedChanges else { return .terminateNow }

        return UnsavedChangesAlert.confirmDiscard(actionTitle: "Discard and Quit") ? .terminateNow : .terminateCancel
    }
}

// Asks before closing a window that has unsaved edits. SwiftUI has no
// "should close" hook on macOS 14, so this sits in front of the window's
// own delegate and passes everything else through to it.
struct WindowCloseGuard: NSViewRepresentable {
    let tracker: UnsavedChangesTracker

    func makeNSView(context: Context) -> NSView {
        GuardView(tracker: tracker)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GuardView: NSView {
        private let tracker: UnsavedChangesTracker
        private var proxy: WindowDelegateProxy?

        init(tracker: UnsavedChangesTracker) {
            self.tracker = tracker
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard let window, proxy == nil else { return }

            // Next run loop, so SwiftUI has installed its own delegate first.
            DispatchQueue.main.async { [weak self] in
                self?.install(on: window)
            }
        }

        private func install(on window: NSWindow) {
            guard proxy == nil else { return }

            let newProxy: WindowDelegateProxy = WindowDelegateProxy(original: window.delegate, tracker: tracker)
            window.delegate = newProxy
            // The window only holds its delegate weakly.
            proxy = newProxy
        }
    }
}

@MainActor
private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    // Held strongly: once replaced, the window no longer keeps it alive.
    private let original: NSWindowDelegate?
    private let tracker: UnsavedChangesTracker

    init(original: NSWindowDelegate?, tracker: UnsavedChangesTracker) {
        self.original = original
        self.tracker = tracker
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if tracker.hasUnsavedChanges, !UnsavedChangesAlert.confirmDiscard(actionTitle: "Discard and Close") {
            return false
        }

        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) {
            return original
        }

        return super.forwardingTarget(for: aSelector)
    }
}
