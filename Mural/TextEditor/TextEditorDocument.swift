import AppKit
import Foundation
import MuralKit
import Observation
import StretchText

/// O documento do editor de texto: o Markdown que vira o texto do cartão, mais o que ainda não está num mural.
///
/// `text` é a fonte da verdade. Um cartão embutido é a linha `![título](mural-card:<UUID>)` e uma imagem ainda não gravada é a
/// linha `![Colando imagem…](mural-colando:<TOKEN>)`, cada uma num bloco próprio, separada do texto por uma linha em branco. O
/// conteúdo das linhas fica em `embeds` e em `images`, só na memória: nada é gravado em disco aqui.
///
/// Com o campo de texto montado (`attach(_:)`), as edições passam pela ponte e portanto pelo ⌘Z do campo; sem ele (testes, o
/// documento ainda sem janela), mexem direto em `text`.
@MainActor @Observable
final class TextEditorDocument {
    /// O Markdown.
    var text = "" {
        didSet { if text != oldValue { scheduleSuggestion() } }
    }

    /// Os cartões embutidos citados no texto, pelo `UUID` da linha. Ficam mesmo depois de a linha sair do texto, para o ⌘Z poder
    /// trazê-la de volta; só `clear()` os descarta.
    var embeds: [UUID: EmbeddedCard] = [:] {
        didSet { scheduleSuggestion() }
    }

    /// As imagens coladas, pelo marcador da linha provisória; só na memória, até serem coladas num mural.
    var images: [UUID: NoteImagePaste.Source] = [:] {
        didSet { scheduleSuggestion() }
    }

    /// A seleção em `text`; `nil` sem seleção (o cursor no fim).
    var selection: Range<String.Index>?

    /// O que sugerir para guardar o texto. Recalculado 150 ms depois da última mudança: `PasteKindDetector` lê o texto inteiro
    /// (endereços, marcadores de lista) e a cada tecla isso é trabalho à toa e faz as opções piscarem; esperar a pausa na
    /// digitação dá uma sugestão estável.
    private(set) var suggestion = PasteKindSuggestion(suggested: .text, options: [])

    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private weak var bridge: EditorAttachmentBridge?

    /// O tempo que a sugestão espera depois da última mudança; os testes usam um valor curto.
    @ObservationIgnored let suggestionDelay: Duration

    /// As imagens já decodificadas, uma vez por marcador: o campo refaz os anexos a cada recarga, e decodificar de novo a cada vez
    /// seria trabalho à toa.
    @ObservationIgnored private var decodedImages: [UUID: NSImage] = [:]

    init(suggestionDelay: Duration = .milliseconds(150)) {
        self.suggestionDelay = suggestionDelay
    }

    /// Sem texto, cartão nem imagem.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// O Markdown a entregar ao mural: sem as quebras do fim, como a linha livre que fica depois de um cartão inserido por último.
    var deliverableText: String {
        var result = text
        while result.last?.isNewline == true { result.removeLast() }
        return result
    }

    /// Palavras do texto, sem contar as linhas dos cartões e das imagens.
    var wordCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !EditorAttachmentBridge.isBlockLine($0) }
            .reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
    }

    /// O texto tem linhas de cartões embutidos.
    var hasEmbeds: Bool {
        !NoteImageMarkup.references(in: text).cardIDs.isEmpty
    }

    /// O texto tem imagens ainda por gravar.
    var hasImages: Bool {
        text.split(separator: "\n").contains { NoteImageMarkup.isPendingLine($0) }
    }

    /// A ponte do campo de texto montado.
    func attach(_ bridge: EditorAttachmentBridge) {
        self.bridge = bridge
    }

    /// Acha o que mostrar para uma linha de bloco: o cartão ou a imagem que o documento guarda para ela.
    func content(forLine line: String) -> EmbeddedTextAttachment.Content? {
        guard let image = MarkdownImage.parse(line[...]) else { return nil }
        if let id = NoteImageMarkup.cardID(inSource: image.source), let card = embeds[id] {
            return .card(card, title: image.alt)
        }
        guard NoteImageMarkup.isPendingSource(image.source),
            let token = UUID(uuidString: String(image.source.dropFirst("mural-colando:".count))),
            let source = images[token]
        else { return nil }
        return .image(decodedImage(for: token, from: source), alt: image.alt)
    }

    private func decodedImage(for token: UUID, from source: NoteImagePaste.Source) -> NSImage? {
        if let cached = decodedImages[token] { return cached }
        guard let image = Self.image(from: source) else { return nil }
        decodedImages[token] = image
        return image
    }

    // MARK: Edição

    /// Insere um cartão embutido por item, cada um num bloco próprio, no cursor.
    func insertCards(_ cards: [EmbeddedCard]) {
        var lines: [String] = []
        for card in cards {
            let id = UUID()
            embeds[id] = card
            lines.append(NoteImageMarkup.cardLine(id: id, title: card.title))
        }
        insertBlocks(lines)
    }

    /// Insere uma imagem por fonte, cada uma num bloco próprio, no cursor, como linha provisória.
    func insertImages(_ sources: [NoteImagePaste.Source]) {
        var lines: [String] = []
        for source in sources {
            let token = UUID()
            images[token] = source
            lines.append(NoteImageMarkup.pendingLine(token: token))
        }
        insertBlocks(lines)
    }

    /// Insere o texto no cursor, no lugar da seleção.
    func insertText(_ string: String) {
        if let bridge {
            bridge.replaceSelection(withMarkdown: string)
            return
        }
        let range = selection ?? text.endIndex..<text.endIndex
        text.replaceSubrange(range, with: string)
        let end = text.index(range.lowerBound, offsetBy: string.count, limitedBy: text.endIndex) ?? text.endIndex
        selection = end..<end
    }

    /// Trata o que o colar trouxe: cartões, imagens (e o texto entre elas).
    /// - Returns: `false` para texto simples e para nada, que seguem o caminho do campo.
    func paste(_ paste: TextEditorPaste) -> Bool {
        switch paste {
        case .contacts, .music, .links:
            insertCards(paste.embeddedCards)
        case .images(let pieces):
            for piece in pieces {
                switch piece {
                case .text(let string): insertText(string)
                case .image(let source): insertImages([source])
                }
            }
        case .text(let string):
            // Texto copiado do próprio editor traz as linhas dos cartões: as que o documento conhece voltam a ser anexos, e as de
            // outros documentos ficam como texto.
            guard string.split(separator: "\n").contains(where: EditorAttachmentBridge.isBlockLine) else { return false }
            insertText(string)
        case .nothing:
            return false
        }
        return true
    }

    /// Aplica a formatação à seleção (ao texto todo, sem seleção), desfazível quando há campo.
    ///
    /// As linhas dos cartões e das imagens nunca são formatadas: o trecho é dividido nelas, a formatação vale para cada pedaço de
    /// texto e cada linha de bloco volta igual, na sua própria linha. As formatações de linha ampliam a seleção para as linhas
    /// inteiras, e as quebras e espaços das pontas voltam como estavam (como em `PasteTextFormat.apply(to:selection:)`).
    func applyFormat(_ format: PasteTextFormat, locale: Locale = .current) {
        var range = selection.flatMap { $0.isEmpty ? nil : $0 } ?? text.startIndex..<text.endIndex
        if format.formatsWholeLines { range = text.lineRange(for: range) }
        let piece = text[range]
        guard let first = piece.firstIndex(where: { !$0.isWhitespace }), let last = piece.lastIndex(where: { !$0.isWhitespace })
        else { return }
        let leading = String(piece[..<first])
        let core = piece[first...last]
        let trailing = String(piece[piece.index(after: last)...])

        let formatted = Self.formatted(core, with: format, locale: locale)
        let newText = String(text[..<range.lowerBound]) + leading + formatted + trailing + text[range.upperBound...]
        guard newText != text else { return }
        let lower = text.utf16.distance(from: text.startIndex, to: range.lowerBound) + leading.utf16.count
        let selectionRange = lower..<(lower + formatted.utf16.count)
        if let bridge {
            bridge.replaceMarkdown(with: newText)
            bridge.select(markdownRange: selectionRange)
        } else {
            text = newText
            selection =
                String.Index(
                    utf16Offset: selectionRange.lowerBound, in: newText)..<String.Index(utf16Offset: selectionRange.upperBound, in: newText)
        }
    }

    /// O trecho formatado: cada pedaço de linhas de texto seguidas é formatado à parte e as linhas de bloco ficam como estão.
    private static func formatted(_ piece: Substring, with format: PasteTextFormat, locale: Locale) -> String {
        var output: [String] = []
        var run: [Substring] = []
        func flush() {
            guard !run.isEmpty else { return }
            output.append(format.applyKeepingNonEmpty(to: run.joined(separator: "\n"), locale: locale))
            run = []
        }
        for line in piece.split(separator: "\n", omittingEmptySubsequences: false) {
            if EditorAttachmentBridge.isBlockLine(line) {
                flush()
                output.append(String(line))
            } else {
                run.append(line)
            }
        }
        flush()
        return output.joined(separator: "\n")
    }

    /// Negrito ou itálico na seleção (`MarkdownEmphasis`), desfazível quando há campo. Uma seleção que toca a linha de um cartão
    /// ou de uma imagem não muda nada: os asteriscos quebrariam a linha de bloco.
    func applyEmphasis(_ emphasis: MarkdownEmphasis) {
        let range = selection ?? text.endIndex..<text.endIndex
        let touched = text[text.lineRange(for: range)]
        guard !touched.split(separator: "\n").contains(where: EditorAttachmentBridge.isBlockLine) else { return }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        let result = emphasis.toggle(in: text, selection: lower..<upper)
        guard result.text != text else { return }
        let newLower = result.text.index(result.text.startIndex, offsetBy: result.selection.lowerBound)
        let newUpper = result.text.index(result.text.startIndex, offsetBy: result.selection.upperBound)
        let utf16Range =
            result.text.utf16.distance(
                from: result.text.startIndex, to: newLower)..<result.text.utf16.distance(from: result.text.startIndex, to: newUpper)
        if let bridge {
            bridge.replaceMarkdown(with: result.text)
            bridge.select(markdownRange: utf16Range)
        } else {
            text = result.text
            selection = newLower..<newUpper
        }
    }

    /// Esvazia o documento: texto, seleção, cartões e imagens, inclusive os que o ⌘Z poderia trazer de volta.
    func clear() {
        text = ""
        selection = nil
        embeds = [:]
        images = [:]
        decodedImages = [:]
        bridge?.reload("")
    }

    /// Chamado pelo campo quando o texto ou a seleção mudaram: guarda o Markdown e a seleção nele.
    ///
    /// A seleção chega em unidades UTF-16 do Markdown (as do `NSRange`) e vira `String.Index` pela visão UTF-16 da string: as
    /// pontas caem em fronteiras de escalar, porque vêm de edições do campo.
    func sync(markdown: String, selectionUTF16 range: Range<Int>?) {
        if text != markdown { text = markdown }
        selection = range.map {
            String.Index(
                utf16Offset: min($0.lowerBound, markdown.utf16.count), in: markdown)..<String.Index(
                    utf16Offset: min($0.upperBound, markdown.utf16.count), in: markdown)
        }
    }

    // MARK: Interno

    private func insertBlocks(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        if let bridge {
            bridge.insertBlocks(lines)
            return
        }
        let range = selection ?? text.endIndex..<text.endIndex
        let inserted = NoteImageMarkup.insertion(of: lines, after: text[..<range.lowerBound], before: text[range.upperBound...])
        text.replaceSubrange(range, with: inserted)
        let end = text.index(range.lowerBound, offsetBy: inserted.count, limitedBy: text.endIndex) ?? text.endIndex
        selection = end..<end
    }

    private func scheduleSuggestion() {
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: self?.suggestionDelay ?? .zero)
            guard !Task.isCancelled, let self else { return }
            self.suggestion = PasteKindDetector.detect(text: self.text, hasEmbeds: self.hasEmbeds, hasImages: self.hasImages)
        }
    }

    private static func image(from source: NoteImagePaste.Source) -> NSImage? {
        switch source {
        case .file(let url): NSImage(contentsOf: url)
        case .data(let data, _), .needsPNGConversion(let data): NSImage(data: data)
        }
    }
}
