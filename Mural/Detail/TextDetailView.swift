import MuralKit
import SwiftUI

/// Nota em página de leitura (Markdown com parágrafos dobráveis), ou post-it ampliado;
/// no modo de edição, o editor de cada um.
struct TextDetailView: View {
    let item: BoardItem
    let model: BoardModel?
    let session: BoardWindowSession?

    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = DetailScrollMetrics()
    @State private var savedPosition: ReadingPosition?
    @State private var restoring = false
    @State private var presentationToken: ReadingPresentationToken?

    var body: some View {
        if let session, session.editingItemID == item.id {
            if item.kind == .sticky {
                StickyEditorView(itemID: item.id, session: session)
            } else {
                NoteEditorView(itemID: item.id, session: session)
                    .frame(maxWidth: 680, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 100)
                    .padding(.bottom, 90)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity)
            }
        } else if item.kind == .sticky {
            ScrollView {
                Text(item.displayText)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(Theme.stickyInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(36)
            }
            .frame(width: 420, height: 420)
            .background(Theme.sticky(item.stickyColor), in: .rect(cornerRadius: 6))
            .cardShadow()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                NotePageContent(item: item, model: model, session: session)
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(.top, 110)
                    .padding(.bottom, 110)
                    .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .discreetScrollIndicators()
            .onScrollGeometryChange(for: DetailScrollMetrics.self) { geometry in
                DetailScrollMetrics(geometry)
            } action: { _, newMetrics in
                metrics = newMetrics
                confirmRestoreIfPossible()
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                capturePosition()
            }
            .task(id: item.id) { beginRestore() }
            .allowsHitTesting(!restoring)
            .readingRestoreTimeout(isRestoring: restoring) {
                restoring = false
                if let token = presentationToken { _ = session?.finishReadingRestore(token: token) }
            }
            .accessibilityHidden(restoring)
        }
    }

    private func beginRestore() {
        guard let session else { return }
        let token = session.readingPresentationToken(for: item.id)
        presentationToken = token
        savedPosition = session.beginReadingRestore(token: token)
        guard case .item = savedPosition else {
            restoring = false
            _ = session.finishReadingRestore(token: token)
            return
        }
        restoring = true
        confirmRestoreIfPossible()
    }

    private func confirmRestoreIfPossible() {
        guard restoring, let session, let token = presentationToken,
            session.acceptsReadingPresentation(token), let savedPosition,
            metrics.containerSize != .zero, metrics.contentSize != .zero,
            let targetY = ReadingPosition.itemTargetY(
                savedPosition,
                contentHeight: metrics.contentSize.height,
                viewportHeight: metrics.containerSize.height,
                contentInsetsTop: metrics.contentInsets.top,
                contentInsetsBottom: metrics.contentInsets.bottom)
        else { return }
        if abs(metrics.visibleRect.minY - targetY) > 1 {
            scrollPosition.scrollTo(y: targetY)
            return
        }
        restoring = false
        _ = session.finishReadingRestore(token: token)
    }

    private func capturePosition() {
        guard !restoring, let session, let token = presentationToken,
            session.acceptsReadingPresentation(token),
            session.restorationPhase == .ready
        else { return }
        let position = ReadingPosition.item(itemID: item.id, visibleContentY: max(0, metrics.visibleRect.minY))
        session.recordReadingPosition(position, token: token)
    }
}
