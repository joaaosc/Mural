import MuralKit
import SwiftUI

/// Imagem centralizada com a paleta à esquerda, metadados à direita e legenda editável embaixo.
struct ImageDetailView: View {
    let item: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?

    @State private var caption = ""
    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = DetailScrollMetrics()
    @State private var savedPosition: ReadingPosition?
    @State private var restoring = false
    @State private var presentationToken: ReadingPresentationToken?

    private var ratio: CGFloat { BoardLayout.aspectRatio(for: item) }

    private var rows: [(label: String, value: String)] {
        let date = item.createdAt.formatted(.dateTime.day().month(.twoDigits).year())
        guard let meta = item.imageMetadata else { return [("Data", date)] }
        var rows = [("Resolução", meta.resolutionText), ("Tamanho", meta.fileSizeText), ("Data", date)]
        if let profile = meta.colorProfile { rows.append(("Perfil de cor", profile)) }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(alignment: .top, spacing: 22) {
                    PaletteColumn(colors: item.imageMetadata?.palette ?? [])
                        .frame(width: 30)
                    ThumbnailView(url: model.fileURL(for: item), kind: .image, maxPixelSize: 2400, contentMode: .fit)
                        .aspectRatio(ratio, contentMode: .fit)
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.62 }
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityLabel(item.title)
                    MetadataColumn(rows: rows)
                        .frame(width: 170, alignment: .leading)
                }
                TextField("Adicionar legenda…", text: $caption, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.reading)
                    .lineLimit(1...8)
                    .frame(maxWidth: 440)
                    .task(id: caption) {
                        // Grava meio segundo depois da última tecla, não a cada tecla.
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        saveCaptionIfChanged()
                    }
            }
            .padding(.top, 80)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($scrollPosition)
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
        .discreetScrollIndicators()
        .task(id: item.id) {
            beginRestore()
            caption = session?.captionDraft(for: item.id) ?? item.text ?? ""
        }
        .onChange(of: caption) { _, text in
            session?.setCaptionDraft(text, for: item.id)
        }
        // Sair da tela cancela a espera acima: grava aqui o que ainda não foi gravado.
        .onDisappear {
            session?.setCaptionDraft(caption, for: item.id)
            session?.commitCaptionDrafts()
            saveCaptionIfChanged()
        }
        .allowsHitTesting(!restoring)
        .accessibilityHidden(restoring)
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

    private func saveCaptionIfChanged() {
        guard caption != (model.item(id: item.id)?.text ?? "") else { return }
        model.setCaption(caption, for: item.id)
    }
}
