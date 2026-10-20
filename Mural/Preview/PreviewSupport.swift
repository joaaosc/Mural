#if DEBUG
import AppKit
import MuralKit
import SwiftUI

extension BoardModel {
    /// Mural de exemplo numa pasta temporária, com imagens geradas na hora
    /// (nenhum arquivo de imagem é versionado no projeto).
    static func preview() -> BoardModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralPreview-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: directory))
        let folder = model.rootItems.first { $0.kind == .folder && $0.title == "The Cottage" }
        let swatches: [(String, [Color], CGSize)] = [
            (
                "Terracota", [Color(red: 0.93, green: 0.42, blue: 0.33), Color(red: 0.45, green: 0.22, blue: 0.16)],
                CGSize(width: 600, height: 900)
            ),
            (
                "Carvalho", [Color(red: 0.80, green: 0.62, blue: 0.42), Color(red: 0.30, green: 0.20, blue: 0.12)],
                CGSize(width: 900, height: 1200)
            ),
            (
                "Pátio", [Color(red: 0.95, green: 0.93, blue: 0.88), Color(red: 0.55, green: 0.55, blue: 0.52)],
                CGSize(width: 800, height: 1000)
            ),
        ]
        for (title, colors, size) in swatches {
            if let data = PreviewImages.png(colors: colors, size: size) {
                model.importData(data, fileExtension: "png", kind: .image, title: title, into: folder?.id)
            }
        }
        if let data = PreviewImages.png(colors: [.indigo, .orange], size: CGSize(width: 700, height: 900)) {
            model.importData(data, fileExtension: "png", kind: .image, title: "Gato", into: nil)
        }
        return model
    }
}

enum PreviewImages {
    @MainActor
    static func png(colors: [Color], size: CGSize) -> Data? {
        let renderer = ImageRenderer(
            content:
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: size.width, height: size.height)
        )
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

#Preview("Mural", traits: .fixedLayout(width: 1100, height: 720)) {
    @Previewable @Namespace var namespace
    let model = BoardModel.preview()
    BoardCanvasView(
        model: model,
        hero: HeroContext(namespace: namespace, isEnabled: false, presented: []),
        filter: nil,
        zoom: CanvasZoomController(),
        onOpen: { _ in },
        onAdd: {},
        boardID: BoardID(),
        generation: 0
    )
}

#Preview("Coleção", traits: .fixedLayout(width: 1100, height: 720)) {
    @Previewable @Namespace var namespace
    let model = BoardModel.preview()
    let folder = model.rootItems.first { $0.kind == .folder && $0.title == "The Cottage" }!
    CollectionView(
        folder: folder, model: model, session: nil, hero: HeroContext(namespace: namespace, isEnabled: false, presented: []), filter: nil,
        isInfoPresented: .constant(false)
    ) {
        _ in
    }
    .background(Theme.canvas)
}

#Preview("Detalhe da imagem", traits: .fixedLayout(width: 1100, height: 720)) {
    let model = BoardModel.preview()
    let image = model.rootItems.first { $0.kind == .image }!
    ItemDetailView(item: image, model: model, session: nil, onClose: {})
        .background(Theme.page)
}

#Preview("Lista", traits: .fixedLayout(width: 1100, height: 720)) {
    let model = BoardModel.preview()
    let list = model.rootItems.first { $0.kind == .checklist }!
    ItemDetailView(item: list, model: model, session: nil, onClose: {})
        .background(Theme.page)
}
#endif
