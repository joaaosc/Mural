import MuralKit
import PDFKit
import SwiftUI

/// Ponte para o `PDFView` do PDFKit, que não tem equivalente em SwiftUI.
struct PDFKitView: NSViewRepresentable {
    let itemID: UUID
    let url: URL
    let session: BoardWindowSession?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.update(url: url, in: view)
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.restore(in: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(itemID: itemID, url: url, session: session)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator: NSObject {
        let itemID: UUID
        var url: URL
        weak var session: BoardWindowSession?
        private var observers: [NSObjectProtocol] = []
        private var pendingCapture: Task<Void, Never>?
        private var savedPosition: ReadingPosition?
        private var isRestoring = true
        private var restoreApplied = false

        init(itemID: UUID, url: URL, session: BoardWindowSession?) {
            self.itemID = itemID
            self.url = url
            self.session = session
            super.init()
        }

        func install(on view: PDFView) {
            if let session {
                savedPosition = session.beginReadingRestore(
                    for: itemID,
                    boardID: session.boardID,
                    generation: session.generation,
                    navigationGeneration: session.navigationGeneration)
            } else {
                isRestoring = false
            }
            let center = NotificationCenter.default
            for name in [
                Notification.Name.PDFViewPageChanged,
                Notification.Name.PDFViewScaleChanged,
                Notification.Name.PDFViewVisiblePagesChanged,
            ] {
                observers.append(
                    center.addObserver(forName: name, object: view, queue: .main) { [weak self, weak view] _ in
                        Task { @MainActor [weak self, weak view] in
                            guard let self, let view else { return }
                            self.restoreDidChange(in: view)
                        }
                    })
            }
            restore(in: view)
        }

        func update(url: URL, in view: PDFView) {
            guard self.url != url else { return }
            self.url = url
            isRestoring = true
            restoreApplied = false
            if let session {
                savedPosition = session.beginReadingRestore(
                    for: itemID,
                    boardID: session.boardID,
                    generation: session.generation,
                    navigationGeneration: session.navigationGeneration)
            }
            restore(in: view)
        }

        func restore(in view: PDFView) {
            guard let document = view.document, document.pageCount > 0 else {
                isRestoring = false
                session?.finishReadingRestore(for: itemID)
                return
            }
            guard case .pdf(_, let pageIndex, let scale, let point) = savedPosition else {
                view.autoScales = true
                isRestoring = false
                session?.finishReadingRestore(for: itemID)
                return
            }
            let page = document.page(at: min(max(0, pageIndex), document.pageCount - 1))!
            let bounds = page.bounds(for: .mediaBox)
            let boundedScale = min(max(scale.isFinite ? scale : view.scaleFactorForSizeToFit, view.minScaleFactor), view.maxScaleFactor)
            view.autoScales = false
            view.scaleFactor = boundedScale
            let boundedPoint = CGPoint(
                x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
            view.go(to: PDFDestination(page: page, at: boundedPoint))
            restoreApplied = true
        }

        func restoreDidChange(in view: PDFView) {
            guard isRestoring else {
                scheduleCapture(in: view)
                return
            }
            guard restoreApplied else { return }
            isRestoring = false
            session?.finishReadingRestore(for: itemID)
        }

        private func scheduleCapture(in view: PDFView) {
            guard let session,
                session.restorationPhase == .ready,
                session.acceptsPersistence(for: session.boardID, generation: session.generation),
                view.currentDestination != nil,
                view.document != nil
            else { return }
            let callbackBoardID = session.boardID
            let callbackGeneration = session.generation
            let callbackNavigationGeneration = session.navigationGeneration
            pendingCapture?.cancel()
            pendingCapture = Task { [weak self, weak view] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, let view, !Task.isCancelled,
                    let destination = view.currentDestination,
                    let page = destination.page,
                    let document = view.document
                else { return }
                let index = document.index(for: page)
                let bounds = page.bounds(for: .mediaBox)
                let position = ReadingPosition.clampedPDF(
                    itemID: self.itemID,
                    pageIndex: index,
                    pageCount: document.pageCount,
                    scale: Double(view.scaleFactor),
                    scaleRange: Double(view.minScaleFactor)...Double(view.maxScaleFactor),
                    pointInPage: BoardPoint(x: destination.point.x, y: destination.point.y),
                    pageBounds: bounds)
                self.session?.recordReadingPosition(
                    position,
                    boardID: callbackBoardID,
                    generation: callbackGeneration,
                    navigationGeneration: callbackNavigationGeneration)
            }
        }

        func invalidate() {
            pendingCapture?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            session?.finishReadingRestore(for: itemID)
        }
    }
}
