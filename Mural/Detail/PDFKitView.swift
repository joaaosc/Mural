import AppKit
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
        let urlChanged = context.coordinator.update(url: url, in: view)
        if urlChanged || view.document?.documentURL != url {
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
        weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []
        private var pendingCapture: Task<Void, Never>?
        private var savedPosition: ReadingPosition?
        private var presentationToken: ReadingPresentationToken?
        private var isRestoring = true
        private var restoreApplied = false
        private var expectedPageIndex: Int?
        private var expectedScale: CGFloat?
        private var expectedPoint: CGPoint?
        private var hasFrameObserver = false
        private var didFinalizePresentation = false
        private(set) var restoreCallbackCount = 0
        /// Quantas vezes o destino salvo foi reaplicado nesta apresentação.
        private var restoreAttempts = 0
        /// Prazo para aceitar a posição alcançada; sem ele, cada rolagem do usuário
        /// reaplicaria o destino salvo enquanto a confirmação exata não chegasse.
        private var restoreDeadline: Task<Void, Never>?
        static let maxRestoreAttempts = 4
        static let restoreTimeout: Duration = .milliseconds(1500)
        weak var observedClipView: NSClipView?

        init(itemID: UUID, url: URL, session: BoardWindowSession?) {
            self.itemID = itemID
            self.url = url
            self.session = session
            super.init()
        }

        func install(on view: PDFView) {
            pdfView = view
            if let session {
                let token = session.readingPresentationToken(for: itemID)
                presentationToken = token
                savedPosition = session.beginReadingRestore(token: token)
                session.registerReadingFinalizer(for: token) { [weak self] in
                    self?.finalizeBeforeNavigation()
                }
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
            installLayoutObservers(on: view)
            restore(in: view)
        }

        @discardableResult
        func update(url: URL, in view: PDFView) -> Bool {
            guard self.url != url else { return false }
            publishFinalCapture(in: view)
            pendingCapture?.cancel()
            pendingCapture = nil
            if let presentationToken {
                _ = session?.finishReadingRestore(token: presentationToken)
                session?.unregisterReadingFinalizer(for: presentationToken)
            }
            self.url = url
            didFinalizePresentation = false
            isRestoring = session != nil
            restoreApplied = false
            restoreAttempts = 0
            restoreDeadline?.cancel()
            restoreDeadline = nil
            expectedPageIndex = nil
            expectedScale = nil
            expectedPoint = nil
            if let session {
                let token = session.readingPresentationToken(for: itemID)
                presentationToken = token
                savedPosition = session.beginReadingRestore(token: token)
                session.registerReadingFinalizer(for: token) { [weak self] in
                    self?.finalizeBeforeNavigation()
                }
            } else {
                presentationToken = nil
                savedPosition = nil
            }
            return true
        }

        func restore(in view: PDFView) {
            installLayoutObservers(on: view)
            guard let document = view.document, document.pageCount > 0 else {
                finishUnavailableRestore(in: view)
                return
            }
            guard view.bounds.width > 0, view.bounds.height > 0,
                view.visibleRect.width > 0, view.visibleRect.height > 0
            else { return }
            guard case .pdf(_, let pageIndex, let scale, let point) = savedPosition else {
                expectedPageIndex = nil
                expectedScale = nil
                expectedPoint = nil
                view.autoScales = true
                restoreApplied = true
                confirmRestore(in: view)
                return
            }
            guard let page = document.page(at: min(max(0, pageIndex), document.pageCount - 1)) else {
                finishUnavailableRestore(in: view)
                return
            }
            guard restoreAttempts < Self.maxRestoreAttempts else {
                acceptReachedPosition()
                return
            }
            restoreAttempts += 1
            startRestoreDeadline()
            let bounds = page.bounds(for: .mediaBox)
            let boundedScale = min(max(scale.isFinite ? scale : view.scaleFactorForSizeToFit, view.minScaleFactor), view.maxScaleFactor)
            view.autoScales = false
            view.scaleFactor = boundedScale
            let boundedPoint = CGPoint(
                x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
            expectedPageIndex = document.index(for: page)
            expectedScale = boundedScale
            expectedPoint = boundedPoint
            view.go(to: PDFDestination(page: page, at: boundedPoint))
            restoreApplied = true
            confirmRestore(in: view)
        }

        func restoreDidChange(in view: PDFView) {
            restoreCallbackCount += 1
            guard isRestoring else {
                scheduleCapture(in: view)
                return
            }
            restore(in: view)
            confirmRestore(in: view)
        }

        private func confirmRestore(in view: PDFView) {
            guard isRestoring, restoreApplied, let document = view.document,
                let destination = view.currentDestination,
                let page = destination.page
            else { return }
            if let expectedPageIndex, let expectedScale, let expectedPoint {
                guard document.index(for: page) == expectedPageIndex,
                    abs(view.scaleFactor - expectedScale) <= 0.01,
                    abs(destination.point.x - expectedPoint.x) <= 1,
                    abs(destination.point.y - expectedPoint.y) <= 1
                else { return }
            }
            acceptReachedPosition()
        }

        /// Libera a leitura onde o PDF estiver: o PDFKit pode ajustar o ponto do destino
        /// alguns pontos (margens, fim do documento) e a confirmação exata nunca chegaria.
        private func acceptReachedPosition() {
            restoreDeadline?.cancel()
            restoreDeadline = nil
            guard isRestoring else { return }
            isRestoring = false
            if let presentationToken {
                _ = session?.finishReadingRestore(token: presentationToken)
            }
        }

        private func startRestoreDeadline() {
            guard restoreDeadline == nil else { return }
            restoreDeadline = Task { [weak self] in
                try? await Task.sleep(for: Self.restoreTimeout)
                guard let self, !Task.isCancelled else { return }
                self.restoreDeadline = nil
                self.acceptReachedPosition()
            }
        }

        private func finishUnavailableRestore(in view: PDFView) {
            restoreDeadline?.cancel()
            restoreDeadline = nil
            guard isRestoring else { return }
            expectedPageIndex = nil
            expectedScale = nil
            expectedPoint = nil
            restoreApplied = false
            view.autoScales = true
            isRestoring = false
            if let presentationToken {
                _ = session?.finishReadingRestore(token: presentationToken)
            }
        }

        private func installLayoutObservers(on view: PDFView) {
            let center = NotificationCenter.default
            if !hasFrameObserver {
                view.postsFrameChangedNotifications = true
                observers.append(
                    center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) {
                        [weak self, weak view] _ in
                        Task { @MainActor [weak self, weak view] in
                            guard let self, let view else { return }
                            self.restoreDidChange(in: view)
                        }
                    })
                hasFrameObserver = true
            }
            guard observedClipView == nil, let clipView = findClipView(in: view) else { return }
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            observers.append(
                center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) {
                    [weak self, weak view] _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.restoreDidChange(in: view)
                    }
                })
        }

        private func findClipView(in view: NSView) -> NSClipView? {
            if let clipView = view as? NSClipView { return clipView }
            for child in view.subviews {
                if let result = findClipView(in: child) { return result }
            }
            return nil
        }

        private func scheduleCapture(in view: PDFView) {
            guard let session,
                session.restorationPhase == .ready,
                session.acceptsPersistence(for: session.boardID, generation: session.presentationGeneration),
                view.currentDestination != nil,
                view.document != nil
            else { return }
            guard let token = presentationToken else { return }
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
                self.session?.recordReadingPosition(position, token: token)
            }
        }

        private func publishFinalCapture(in view: PDFView) {
            guard !isRestoring else { return }
            pendingCapture?.cancel()
            pendingCapture = nil
            captureNow(in: view)
        }

        private func captureNow(in view: PDFView) {
            guard let session, let token = presentationToken,
                session.acceptsReadingPresentation(token),
                session.restorationPhase == .ready,
                let destination = view.currentDestination,
                let page = destination.page,
                let document = view.document
            else { return }
            let bounds = page.bounds(for: .mediaBox)
            let position = ReadingPosition.clampedPDF(
                itemID: itemID,
                pageIndex: document.index(for: page),
                pageCount: document.pageCount,
                scale: Double(view.scaleFactor),
                scaleRange: Double(view.minScaleFactor)...Double(view.maxScaleFactor),
                pointInPage: BoardPoint(x: destination.point.x, y: destination.point.y),
                pageBounds: bounds)
            session.recordReadingPosition(position, token: token)
        }

        /// Chamado pela sessão antes de avançar a geração de navegação. O
        /// token ainda é válido neste ponto; a desmontagem posterior não deve
        /// depender da ordem dos callbacks de SwiftUI.
        private func finalizeBeforeNavigation() {
            guard !didFinalizePresentation else { return }
            didFinalizePresentation = true
            if let pdfView {
                publishFinalCapture(in: pdfView)
            }
            if let presentationToken {
                session?.unregisterReadingFinalizer(for: presentationToken)
            }
        }

        func invalidate() {
            finalizeBeforeNavigation()
            pendingCapture?.cancel()
            restoreDeadline?.cancel()
            restoreDeadline = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let presentationToken {
                _ = session?.finishReadingRestore(token: presentationToken)
                session?.unregisterReadingFinalizer(for: presentationToken)
            }
            presentationToken = nil
        }

    }
}
