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
        // Só troca o callback. A janela observada muda em `viewDidMoveToWindow`: o SwiftUI
        // também chama esta atualização enquanto a janela está sendo destruída, e observar
        // a janela nesse instante derrubava o app.
        nsView.onWillClose = onWillClose
    }

    static func dismantleNSView(_ nsView: WindowLifecycleObserverView, coordinator: ()) {
        nsView.stopObservingWindow()
    }
}

@MainActor
final class WindowLifecycleObserverView: NSView {
    var onWillClose: (@MainActor () -> Void)?

    /// Identidade da janela observada, sem referência a ela: formar uma referência (mesmo
    /// fraca) a uma janela em desalocação aborta o processo (`objc_initWeak`).
    private var observedWindowID: ObjectIdentifier?
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
        let currentID = window.map(ObjectIdentifier.init)
        guard currentID != observedWindowID else { return }
        stopObservingWindow()

        guard let window, let currentID else { return }
        observedWindowID = currentID
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closing = notification.object as AnyObject?,
                ObjectIdentifier(closing) == currentID
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
        observedWindowID = nil
    }
}
