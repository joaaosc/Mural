import MuralKit
import SwiftUI

/// Imagem centralizada com a paleta à esquerda, metadados à direita e legenda editável embaixo.
struct ImageDetailView: View {
    let item: BoardItem
    let model: BoardModel

    @State private var caption = ""

    private var ratio: CGFloat { CardView.aspectRatio(for: item) }

    private var rows: [(label: String, value: String)] {
        guard let meta = item.imageMetadata else { return [("Date", dateText)] }
        var rows = [("Resolution", meta.resolutionText), ("Size", meta.fileSizeText), ("Date", dateText)]
        if let profile = meta.colorProfile { rows.append(("Color profile", profile)) }
        return rows
    }

    private var dateText: String {
        item.createdAt.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year())
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
                    .onChange(of: caption) { model.setCaption(caption, for: item.id) }
            }
            .padding(.top, 80)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
        .onAppear { caption = item.text ?? "" }
    }
}
