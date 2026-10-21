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

/// Cartões de link de exemplo; as imagens e os ícones são gerados na hora numa pasta temporária.
enum PreviewLinks {
    /// Quatro cartões: com imagem e ícone, sem imagem (monograma), com título longo e com resumo longo.
    @MainActor
    static func cards() -> (items: [BoardItem], files: LinkPreviewFiles) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralPreviewLinks-\(UUID().uuidString)", isDirectory: true)
        let files = LinkPreviewFiles(directory: directory)

        func card(
            _ address: String, title: String, siteName: String? = nil, summary: String? = nil,
            image: [Color]? = nil, icon: [Color]? = nil
        ) -> BoardItem {
            let id = UUID()
            let names = try? files.store(
                imageData: image.flatMap { PreviewImages.png(colors: $0, size: CGSize(width: 1_200, height: 630)) },
                iconData: icon.flatMap { PreviewImages.png(colors: $0, size: CGSize(width: 64, height: 64)) },
                for: id)
            let link = LinkInfo(
                url: URL(string: address)!, siteName: siteName, summary: summary,
                previewImageFile: names?.image, iconFile: names?.icon, preview: .ready(fetchedAt: .now))
            return BoardItem(id: id, kind: .link, title: title, link: link)
        }

        let items = [
            card(
                "https://developer.apple.com/design/human-interface-guidelines", title: "Human Interface Guidelines",
                siteName: "Apple Developer",
                summary: "Princípios, padrões e componentes para criar apps com aparência e comportamento naturais.",
                image: [.indigo, .cyan], icon: [.blue, .indigo]),
            card(
                "https://www.1password.com/features", title: "1Password", summary: "Um cofre para senhas, cartões e notas."),
            card(
                "https://example.org/reportagens/cidades",
                title:
                    "Uma reportagem de fôlego sobre o futuro das cidades, da mobilidade e da forma como vamos morar nas próximas décadas",
                siteName: "Revista Exemplo", summary: "Curto.", image: [.orange, .pink]),
            card(
                "https://github.com/apple/swift", title: "apple/swift", siteName: "GitHub",
                summary:
                    "A linguagem de programação Swift: compilador, biblioteca padrão, ferramentas e documentação. Contribuições são bem-vindas, desde correções pequenas até propostas de evolução da linguagem.",
                icon: [.gray, .black]),
        ]
        return (items, files)
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

/// Nota de exemplo em Markdown: título, parágrafos que dobram, lista, citação e código.
enum PreviewText {
    static let note = """
        # Visita à obra

        A visita é na segunda de manhã. Medir a parede norte antes do meio-dia. Levar as amostras de **tecido** e o leque de cores.

        ## Pendências

        - [x] Pedir as luminárias pendentes
        - [ ] Revisar a planta com o cliente
          - Conferir a altura do balcão

        > O cliente quer luz quente em todos os cômodos. Nada de branco frio na sala.

        O orçamento fecha na sexta. Depois disso, qualquer mudança entra como aditivo.

        Uma frase só fica como está.
        """
}

#Preview("Nota em Markdown", traits: .fixedLayout(width: 1100, height: 720)) {
    let model = BoardModel.preview()
    let note = model.importText(PreviewText.note, as: .text)!
    ItemDetailView(item: note, model: model, session: nil, onClose: {})
        .background(Theme.page)
}

#Preview("Lista", traits: .fixedLayout(width: 1100, height: 720)) {
    let model = BoardModel.preview()
    let list = model.rootItems.first { $0.kind == .checklist }!
    ItemDetailView(item: list, model: model, session: nil, onClose: {})
        .background(Theme.page)
}

/// Os cartões de link de exemplo lado a lado, no tamanho que têm no mural (150×170).
private struct LinkCardsRow: View {
    let items: [BoardItem]
    let files: LinkPreviewFiles

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(items) { item in
                LinkCard(item: item)
                    .frame(width: 150, height: 170)
            }
        }
        .environment(\.linkPreviewFiles, files)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

#Preview("Cartões de link", traits: .fixedLayout(width: 752, height: 250)) {
    let sample = PreviewLinks.cards()
    LinkCardsRow(items: sample.items, files: sample.files)
}

#Preview("Cartões de link (escuro)", traits: .fixedLayout(width: 752, height: 250)) {
    let sample = PreviewLinks.cards()
    LinkCardsRow(items: sample.items, files: sample.files)
        .preferredColorScheme(.dark)
}
#endif
