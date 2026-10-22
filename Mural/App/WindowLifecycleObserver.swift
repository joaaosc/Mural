@preconcurrency import AppKit
import SwiftUI

/// A zero-sized AppKit bridge that reports the close notification for the
/// window containing it.  The bridge deliberately observes a specific window
/// instead of installing an `NSWindowDelegate`, so it cannot replace or
/// interfere with a delegate owned by the scene.
struct WindowLifecycleObserver: NSViewRepresentable {
    let onWillClose: @MainActor () -> Void

    func makeNSView(context: Context) -> WindowLifecycleObserverView {
        let view = WindowLifecycleObserverView()
        view.onWillClose = onWillClose
        return view
    }

    func updateNSView(_ nsView: WindowLifecycleObserverView, context: Context) {
        nsView.onWillClose = onWillClose
        nsView.updateWindowObservation()
    }

    static func dismantleNSView(_ nsView: WindowLifecycleObserverView, coordinator: ()) {
        nsView.stopObservingWindow()
    }
}

@MainActor
final class WindowLifecycleObserverView: NSView {
    var onWillClose: (@MainActor () -> Void)?

    private weak var observedWindow: NSWindow?
    private var notificationToken: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservation()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopObservingWindow()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func updateWindowObservation() {
        guard window !== observedWindow else { return }
        stopObservingWindow()

        guard let window else { return }
        observedWindow = window
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] notification in
            guard let self,
                let notificationWindow = notification.object as? NSWindow,
                notificationWindow === window
            else { return }
            Task { @MainActor [weak self] in
                self?.onWillClose?()
            }
        }
    }

    func stopObservingWindow() {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        notificationToken = nil
        observedWindow = nil
    }
}
