import Foundation
import StretchText

/// Conteúdo de um cartão de texto (nota, post-it ou lista) em blocos neutros, prontos para virar
/// texto formatado no app Notas. Puro: não toca em arquivos nem em AppKit.
public enum NoteExport {
    public enum Marker: Equatable, Sendable {
        case bullet
        case ordered(Int)
        case task(done: Bool)
    }

    public enum Block: Equatable, Sendable {
        case title(String)
        case heading(level: Int, text: String)
        /// Com a marcação em linha (`**negrito**`, `*itálico*`, `` `código` ``) ainda no texto.
        case paragraph(String)
        case listItem(marker: Marker, depth: Int, text: String)
        case quote(String)
        case code(String)
        case image(fileName: String, alt: String)
        /// Cartão embutido na nota (música, lembrete ou link), com o título da linha de imagem.
        case card(EmbeddedCard, title: String)
        case rule
    }

    /// Os blocos do cartão; vazio para os tipos que não são texto.
    public static func blocks(for item: BoardItem) -> [Block] {
        switch item.kind {
        case .text:
            var blocks: [Block] = []
            if !isBlank(item.title) { blocks.append(.title(item.title)) }
            blocks.append(contentsOf: markdownBlocks(item.text ?? "", in: item))
            return blocks
        case .sticky:
            let text = item.text ?? ""
            return isBlank(text) ? [] : [.paragraph(text)]
        case .checklist:
            return checklistBlocks(item.checklistDocument)
        case .image, .video, .pdf, .folder, .link, .reminder, .music, .contact:
            return []
        }
    }

    private static func checklistBlocks(_ document: ChecklistDocument) -> [Block] {
        var blocks: [Block] = []
        if !isBlank(document.title) { blocks.append(.title(document.title)) }
        blocks.append(contentsOf: markdownBlocks(document.intro))
        for section in document.sections {
            if !isBlank(section.title) { blocks.append(.heading(level: 2, text: section.title)) }
            for entry in section.entries {
                blocks.append(.listItem(marker: .task(done: entry.isDone), depth: 0, text: entry.text))
            }
        }
        return blocks
    }

    /// Blocos do Markdown inteiro: os parágrafos dobráveis saem na forma longa. Com `item`, uma linha `mural-card:` vira
    /// `.card` se a nota guarda o cartão, e senão um parágrafo com o título.
    private static func markdownBlocks(_ text: String, in item: BoardItem? = nil) -> [Block] {
        guard !isBlank(text) else { return [] }
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(text))
        var state = StretchState(document: result.document)
        for id in result.document.stretchIDs { _ = state.toggle(id) }
        return ReadingBlock.blocks(for: result, state: state).map { block($0, in: item) }
    }

    private static func block(_ reading: ReadingBlock, in item: BoardItem?) -> Block {
        switch reading.kind {
        case .paragraph: .paragraph(reading.text)
        case .heading(let level): .heading(level: level, text: reading.text)
        case .listItem(let marker, let depth):
            switch marker {
            case .bullet?: .listItem(marker: .bullet, depth: depth, text: reading.text)
            case .ordered(let number)?: .listItem(marker: .ordered(number), depth: depth, text: reading.text)
            case .task(let isDone)?: .listItem(marker: .task(done: isDone), depth: depth, text: reading.text)
            // Continuação de um item anterior: sem marcador, vira parágrafo.
            case nil: .paragraph(reading.text)
            }
        case .blockQuote: .quote(reading.text)
        case .codeBlock, .table: .code(reading.text)
        case .thematicBreak: .rule
        case .image(let image):
            if NoteImageMarkup.isCardSource(image.source) {
                if let id = NoteImageMarkup.cardID(inSource: image.source), let card = item?.embeddedCard(id: id) {
                    .card(card, title: reading.text)
                } else {
                    .paragraph(reading.text)
                }
            } else {
                .image(fileName: image.source, alt: reading.text)
            }
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
