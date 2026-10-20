import MuralKit
import SwiftUI

/// Nota de texto em página de leitura, ou post-it ampliado.
struct TextDetailView: View {
    let item: BoardItem
    let session: BoardWindowSession?

    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = DetailScrollMetrics()
    @State private var savedPosition: ReadingPosition?
    @State private var restoring = false

    var body: some View {
        if item.kind == .sticky {
            Text(item.displayText)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(Theme.stickyInk)
                .textSelection(.enabled)
                .padding(36)
                .frame(width: 420, height: 420, alignment: .topLeading)
                .background(Theme.sticky(item.stickyColor), in: .rect(cornerRadius: 6))
                .cardShadow()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.title)
                        .font(.system(size: 40, weight: .bold))
                    Text(item.text ?? "")
                        .font(.system(.title3, design: .serif))
                        .lineSpacing(5)
                }
                .textSelection(.enabled)
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
            .accessibilityHidden(restoring)
        }
    }

    private func beginRestore() {
        guard let session else { return }
        savedPosition = session.beginReadingRestore(
            for: item.id,
            boardID: session.boardID,
            generation: session.generation,
            navigationGeneration: session.navigationGeneration)
        guard case .item = savedPosition else {
            restoring = false
            session.finishReadingRestore(for: item.id)
            return
        }
        restoring = true
        confirmRestoreIfPossible()
    }

    private func confirmRestoreIfPossible() {
        guard restoring, let session, let savedPosition,
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
        session.finishReadingRestore(for: item.id)
    }

    private func capturePosition() {
        guard !restoring, let session,
            session.restorationPhase == .ready,
            session.acceptsPersistence(for: session.boardID, generation: session.generation)
        else { return }
        let position = ReadingPosition.item(itemID: item.id, visibleContentY: max(0, metrics.visibleRect.minY))
        session.recordReadingPosition(
            position,
            boardID: session.boardID,
            generation: session.generation,
            navigationGeneration: session.navigationGeneration)
    }
}
