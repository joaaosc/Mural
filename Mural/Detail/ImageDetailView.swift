import MuralKit
import SwiftUI

/// Imagem centralizada com a paleta à esquerda, metadados à direita e legenda editável embaixo.
struct ImageDetailView: View {
    let item: BoardItem
    let model: BoardModel

    @State private var caption = ""

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
        .discreetScrollIndicators()
        .onAppear { caption = item.text ?? "" }
        // Sair da tela cancela a espera acima: grava aqui o que ainda não foi gravado.
        .onDisappear { saveCaptionIfChanged() }
    }

    private func saveCaptionIfChanged() {
        guard caption != (model.item(id: item.id)?.text ?? "") else { return }
        model.setCaption(caption, for: item.id)
    }
}
