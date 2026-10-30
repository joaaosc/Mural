import AppKit
import MuralKit
import SwiftUI

/// Cartão embutido numa nota, no lugar da linha `![título](mural-card:<UUID>)` do Markdown.
///
/// Na página de leitura desenha o cartão inteiro (`EmbeddedCardScaledContent`): a música toca ou pausa, com o selo do estado, e o
/// link da web abre no navegador; lembrete, contato e link que não é da web só mostram o estado. Na miniatura do mural vira uma
/// linha com o símbolo e o título (`EmbeddedCardCompactRow`), sem botão.
struct EmbeddedCardView: View {
    let card: EmbeddedCard
    /// O `UUID` da linha `mural-card:<UUID>`; é também o id com que a música embutida toca.
    let cardID: UUID
    let title: String
    let item: BoardItem
    let model: BoardModel?
    let maxPixelSize: Int
    var session: BoardWindowSession?

    /// A partir deste `maxPixelSize` a nota está na página de leitura, onde o cartão é desenhado inteiro e é interativo.
    static let interactiveMinimumPixelSize = 1600

    /// Verdadeiro na página de leitura; falso na miniatura.
    static func isInteractive(maxPixelSize: Int) -> Bool {
        maxPixelSize >= interactiveMinimumPixelSize
    }

    var body: some View {
        if !Self.isInteractive(maxPixelSize: maxPixelSize) {
            EmbeddedCardCompactRow(card: card, title: title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EmbeddedCardWording.label(for: card, title: title))
        } else if let action {
            Button(action: action) {
                EmbeddedCardScaledContent(card: card, title: title, phase: phase)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(EmbeddedCardWording.label(for: card, title: title))
            .accessibilityValue(EmbeddedCardWording.playbackValue(for: phase))
            .accessibilityHint(EmbeddedCardWording.hint(for: card) ?? "")
        } else {
            EmbeddedCardScaledContent(card: card, title: title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EmbeddedCardWording.label(for: card, title: title))
        }
    }

    /// O estado do tocador para a música embutida; ocioso para os outros tipos.
    private var phase: MusicCardPhase {
        guard case .music = card else { return .idle }
        return session?.musicPhase(of: cardID) ?? .idle
    }

    /// A ação do toque (`EmbeddedCardAction`), como função; `nil` quando o cartão só mostra o estado.
    private var action: (() -> Void)? {
        switch EmbeddedCardAction.action(for: card, canPlay: session != nil) {
        case .toggleMusic:
            guard let session, case .music(let music) = card else { return nil }
            let embedded = EmbeddedMusic(cardID: cardID, ownerItemID: item.id, music: music, title: title)
            return { Task { await session.toggleEmbeddedMusic(embedded) } }
        case .openLink(let url):
            return { NSWorkspace.shared.open(url) }
        case nil:
            return nil
        }
    }
}

#if DEBUG
/// Uma nota com um cartão embutido de cada tipo, como na página de leitura.
private struct EmbeddedCardSamples: View {
    private static let cards: [(id: UUID, card: EmbeddedCard)] = [
        (
            UUID(),
            .music(
                MusicSnapshot(
                    kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", primaryTextHex: "#ffffff",
                    secondaryTextHex: "#c9d6e8", trackCount: 17))
        ),
        (UUID(), .reminder(ReminderSnapshot(identifier: "", title: "Comprar pão", listTitle: "Casa", listColorHex: "#FF9500"))),
        (UUID(), .link(LinkInfo(url: URL(string: "https://www.apple.com/br/mac")!, pageTitle: "Mac", siteName: "Apple"))),
        (UUID(), .contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal", organization: "Empresa"))),
    ]

    private static var note: BoardItem {
        BoardItem(
            kind: .text, title: "Nota com cartões",
            text: cards.map { NoteImageMarkup.cardLine(id: $0.id, title: $0.card.title) }.joined(separator: "\n\n"),
            attachments: cards.map {
                NoteAttachment(
                    fileName: NoteImageMarkup.cardAttachmentName(for: $0.id), pixelWidth: 0, pixelHeight: 0, card: $0.card)
            })
    }

    var body: some View {
        NotePageContent(item: Self.note, model: nil, session: nil)
            .padding(24)
            .frame(width: 560, alignment: .topLeading)
            .background(Theme.canvas)
    }
}

#Preview("Cartões embutidos, claro", traits: .fixedLayout(width: 560, height: 2_000)) {
    EmbeddedCardSamples().preferredColorScheme(.light)
}

#Preview("Cartões embutidos, escuro", traits: .fixedLayout(width: 560, height: 2_000)) {
    EmbeddedCardSamples().preferredColorScheme(.dark)
}
#endif
