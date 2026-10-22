import MuralKit
import SwiftUI

/// Lista "Things I need": título grande, texto de abertura e seções com itens marcáveis.
struct ChecklistDetailView: View {
    let item: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?

    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = DetailScrollMetrics()
    @State private var savedPosition: ReadingPosition?
    @State private var restoring = false
    @State private var presentationToken: ReadingPresentationToken?

    var body: some View {
        let document = item.checklistDocument
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title)
                        .font(.system(size: 40, weight: .bold))
                    if !document.intro.isEmpty {
                        Text(document.intro)
                            .font(.body.weight(.medium))
                    }
                    let progress = document.progress
                    Text("\(progress.done) de \(progress.total) marcados")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.headline)
                                .padding(.bottom, 2)
                        }
                        ForEach(section.entries) { entry in
                            ChecklistRow(entry: entry) {
                                model.toggleChecklistEntry(entry.id, in: item.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
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
        .scrollPosition($scrollPosition)
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
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: max(0, metrics.visibleRect.minY)), token: token)
    }
}
