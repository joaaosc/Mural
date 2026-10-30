import AppKit
import CoreGraphics
import Foundation
import MuralKit
import StretchText
import SwiftUI
import Testing

@testable import Mural

/// Desenha os cartões embutidos numa nota fora da tela e lê pixels e a árvore de acessibilidade.
@MainActor
@Suite("Cartões embutidos desenhados na nota")
struct EmbeddedCardViewTests {
    private static let ids = (0..<4).map { _ in UUID() }

    private static let cards: [EmbeddedCard] = [
        .music(
            MusicSnapshot(
                kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", primaryTextHex: "#ffffff",
                secondaryTextHex: "#c9d6e8", trackCount: 17)),
        .reminder(ReminderSnapshot(identifier: "", title: "Comprar pão", listTitle: "Casa", listColorHex: "#FF9500")),
        .link(LinkInfo(url: URL(string: "https://www.apple.com/br/mac")!, pageTitle: "Mac", siteName: "Apple")),
        .contact(
            ContactSnapshot(
                givenName: "Fulana", familyName: "de Tal", organization: "Empresa",
                phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")])),
    ]

    private static var note: BoardItem {
        var lines = ["Primeira frase. Segunda frase."]
        var attachments: [NoteAttachment] = []
        for (id, card) in zip(ids, cards) {
            lines.append(NoteImageMarkup.cardLine(id: id, title: card.title))
            attachments.append(
                NoteAttachment(fileName: NoteImageMarkup.cardAttachmentName(for: id), pixelWidth: 0, pixelHeight: 0, card: card))
        }
        lines.append("Terceira frase. Quarta frase.")
        return BoardItem(kind: .text, title: "Nota com cartões", text: lines.joined(separator: "\n\n"), attachments: attachments)
    }

    private func embedded(_ card: EmbeddedCard, id: UUID = UUID(), maxPixelSize: Int) -> EmbeddedCardView {
        EmbeddedCardView(
            card: card, cardID: id, title: card.title, item: Self.note, model: nil, maxPixelSize: maxPixelSize, session: nil)
    }

    // MARK: Pixels

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// Algum pixel não transparente dentro do retângulo (em pontos, do canto superior esquerdo).
        func hasInk(in rect: CGRect) -> Bool {
            for y in Int(rect.minY)..<min(height, Int(rect.maxY)) {
                for x in Int(rect.minX)..<min(width, Int(rect.maxX)) where bytes[(y * width + x) * 4 + 3] > 8 {
                    return true
                }
            }
            return false
        }
    }

    /// Desenha a view no tamanho dado, um pixel por ponto, alinhada ao topo à esquerda.
    private func bitmap(_ view: some View, size: CGSize) throws -> Bitmap {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height, alignment: .topLeading))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return Bitmap(width: image.width, height: image.height, bytes: bytes)
    }

    /// Fração de pixels diferentes entre duas imagens do mesmo tamanho.
    private func differingFraction(_ lhs: Bitmap, _ rhs: Bitmap) -> Double {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return 1 }
        var different = 0
        for pixel in 0..<(lhs.width * lhs.height) {
            let offset = pixel * 4
            if lhs.bytes[offset..<offset + 4] != rhs.bytes[offset..<offset + 4] { different += 1 }
        }
        return Double(different) / Double(lhs.width * lhs.height)
    }

    // MARK: Testes

    @Test("Na miniatura o cartão vira uma linha de texto: sem cartão desenhado e sem botão")
    func thumbnailIsACompactRow() throws {
        for (id, card) in zip(Self.ids, Self.cards) {
            let view = embedded(card, id: id, maxPixelSize: 240)
            let bitmap = try bitmap(view, size: CGSize(width: 300, height: 200))
            #expect(bitmap.hasInk(in: CGRect(x: 0, y: 0, width: 300, height: 14)), "\(card.title): a linha deveria ter texto")
            #expect(!bitmap.hasInk(in: CGRect(x: 0, y: 24, width: 300, height: 176)), "\(card.title): passou de uma linha")
            #expect(!bitmap.hasInk(in: CGRect(x: 200, y: 0, width: 100, height: 14)), "\(card.title): passou da largura do título")
        }
    }

    @Test("Na página de leitura cada tipo é uma tira mais larga que alta, à esquerda, sem passar de 320 × 60 pt")
    func readingPageDrawsAStrip() throws {
        #expect(EmbeddedCardStrip.maximumWidth > 4 * EmbeddedCardStrip.height)
        for (id, card) in zip(Self.ids, Self.cards) {
            let view = embedded(card, id: id, maxPixelSize: 1600)
            let size = CGSize(width: 480, height: 240)
            let bitmap = try bitmap(view, size: size)
            #expect(bitmap.hasInk(in: CGRect(x: 0, y: 0, width: 320, height: 60)), "\(card.title): a tira deveria ser desenhada")
            #expect(bitmap.hasInk(in: CGRect(x: 300, y: 20, width: 20, height: 20)), "\(card.title): a tira deveria chegar a 320 pt")
            #expect(!bitmap.hasInk(in: CGRect(x: 324, y: 0, width: 156, height: 240)), "\(card.title) passou de 320 pt")
            #expect(!bitmap.hasInk(in: CGRect(x: 0, y: 64, width: 480, height: 176)), "\(card.title) passou de 60 pt")
        }
    }

    @Test("A tira diz o artista, a lista, o site e a organização; sem nada a dizer, fica só o título")
    func stripDetail() {
        #expect(EmbeddedCardWording.detail(for: Self.cards[0]) == "The Beatles")
        #expect(EmbeddedCardWording.detail(for: Self.cards[1]) == "Casa")
        #expect(EmbeddedCardWording.detail(for: Self.cards[2]) == "Apple")
        #expect(EmbeddedCardWording.detail(for: Self.cards[3]) == "Empresa")
        let phone = EmbeddedCard.contact(
            ContactSnapshot(givenName: "Ana", phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")]))
        #expect(EmbeddedCardWording.detail(for: phone) == "+55 21 99999-0000")
        #expect(EmbeddedCardWording.detail(for: .contact(ContactSnapshot(givenName: "Ana"))) == nil)
        let missing = EmbeddedCard.reminder(ReminderSnapshot(identifier: "", title: "Sumiu", listTitle: "Casa", isMissing: true))
        #expect(EmbeddedCardWording.detail(for: missing) == "Apagado no Lembretes")
    }

    @Test("Só música com sessão e link da web têm ação; na miniatura nenhum cartão é interativo")
    func actionsOnlyWhereThereIsOne() {
        let web = EmbeddedCard.link(LinkInfo(url: URL(string: "https://example.com/p?utm_source=x&id=1")!))
        let notWeb = EmbeddedCard.link(LinkInfo(url: URL(string: "ftp://example.com/a")!))
        #expect(EmbeddedCardAction.action(for: web, canPlay: false) == .openLink(URL(string: "https://example.com/p?id=1")!))
        #expect(EmbeddedCardAction.action(for: notWeb, canPlay: true) == nil)
        #expect(EmbeddedCardAction.action(for: Self.cards[0], canPlay: true) == .toggleMusic)
        #expect(EmbeddedCardAction.action(for: Self.cards[0], canPlay: false) == nil)
        #expect(EmbeddedCardAction.action(for: Self.cards[1], canPlay: true) == nil)
        #expect(EmbeddedCardAction.action(for: Self.cards[3], canPlay: true) == nil)
        #expect(EmbeddedCardView.isInteractive(maxPixelSize: 1600) && !EmbeddedCardView.isInteractive(maxPixelSize: 240))
    }

    @Test("NoteImageView desenha o cartão embutido, e a linha sem anexo vira um aviso com texto, não uma imagem quebrada")
    func noteImageViewResolvesTheCard() throws {
        let item = Self.note
        let size = CGSize(width: 480, height: 480)
        let found = MarkdownImage(alt: "Abbey Road", source: "mural-card:\(Self.ids[0].uuidString)")
        let card = try bitmap(NoteImageView(image: found, item: item, model: nil, maxPixelSize: 1600), size: size)
        #expect(card.hasInk(in: CGRect(x: 60, y: 10, width: 240, height: 40)), "a tira da música deveria ser desenhada")

        let missing = MarkdownImage(alt: "Sumiu", source: "mural-card:\(UUID().uuidString)")
        let warning = try bitmap(NoteImageView(image: missing, item: item, model: nil, maxPixelSize: 1600), size: size)
        #expect(warning.hasInk(in: CGRect(x: 0, y: 0, width: 200, height: 24)), "o aviso (símbolo e texto) deveria ser desenhado")
        #expect(!warning.hasInk(in: CGRect(x: 0, y: 40, width: 480, height: 440)), "o aviso é uma linha só")
    }

    @Test("O cartão solto e o conteúdo extraído desenham os mesmos pixels")
    func looseCardsMatchTheirContent() throws {
        let size = CGSize(width: 150, height: 210)
        let music = MusicSnapshot(
            kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", primaryTextHex: "#ffffff",
            secondaryTextHex: "#c9d6e8", trackCount: 17)
        let musicItem = BoardItem(kind: .music, title: "Abbey Road", music: music)
        let loose = try bitmap(MusicCard(item: musicItem), size: size)
        let content = try bitmap(MusicCardContent(music: music, title: "Abbey Road"), size: size)
        #expect(differingFraction(loose, content) <= 0.001)

        let link = LinkInfo(url: URL(string: "https://www.apple.com/br/mac")!, pageTitle: "Mac", siteName: "Apple", summary: "Resumo")
        let linkItem = BoardItem(kind: .link, title: "Mac", link: link)
        let linkSize = CGSize(width: 150, height: 170)
        #expect(
            differingFraction(
                try bitmap(LinkCard(item: linkItem), size: linkSize),
                try bitmap(LinkCardContent(link: link, title: "Mac"), size: linkSize)) <= 0.001)
    }

    @Test("Cartão solto sem os dados mostra o papel com o título, não uma área vazia")
    func looseCardsWithoutDataShowTheTitle() throws {
        let size = CGSize(width: 150, height: 210)
        let music = try bitmap(MusicCard(item: BoardItem(kind: .music, title: "Sem dados")), size: size)
        let link = try bitmap(LinkCard(item: BoardItem(kind: .link, title: "Sem dados")), size: size)
        for bitmap in [music, link] {
            #expect(bitmap.hasInk(in: CGRect(x: 8, y: 8, width: 100, height: 14)))
        }
    }

    @Test("Os textos de acessibilidade dizem o tipo, o título e o estado, e só música e link têm dica")
    func wording() {
        #expect(EmbeddedCardWording.label(for: Self.cards[0], title: "Abbey Road") == "Música, Abbey Road")
        #expect(EmbeddedCardWording.label(for: Self.cards[3], title: "  ") == "Contato")
        #expect(EmbeddedCardWording.hint(for: Self.cards[0]) != nil && EmbeddedCardWording.hint(for: Self.cards[2]) != nil)
        #expect(EmbeddedCardWording.hint(for: Self.cards[1]) == nil && EmbeddedCardWording.hint(for: Self.cards[3]) == nil)
        #expect(EmbeddedCardWording.playbackValue(for: .playing) == "tocando")
        #expect(EmbeddedCardWording.playbackValue(for: .paused) == "pausado")
        #expect(EmbeddedCardWording.playbackValue(for: .idle).isEmpty && EmbeddedCardWording.playbackValue(for: .loading).isEmpty)
    }

    @Test("A linha do cartão continua um bloco de imagem que não dobra entre parágrafos dobrados")
    func cardLineStaysAnImageBlock() throws {
        let text = try #require(Self.note.text)
        let segments = TextSegmenter.segment(text).segments
        let images = segments.filter { $0.kind == .image }
        #expect(images.count == Self.cards.count)
        #expect(images.allSatisfy { !$0.isFoldable })
        #expect(segments.filter(\.isFoldable).count == 2)
    }
}
