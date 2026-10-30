import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
@Suite("Documento do editor de texto")
struct TextEditorDocumentTests {
    private let music = EmbeddedCard.music(MusicSnapshot(kind: .album, title: "Abbey Road"))
    private let contact = EmbeddedCard.contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal"))

    /// Espera a sugestão (recalculada depois da pausa) chegar, sem depender de quanto o Mac está ocupado.
    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func cardLines(in document: TextEditorDocument) -> [String] {
        document.text.split(separator: "\n").filter { NoteImageMarkup.isCardSource(String($0)) || $0.contains("](mural-card:") }.map(
            String.init)
    }

    @Test("Cartões entram cada um num bloco próprio, separados por uma linha em branco")
    func insertCardsMakesBlocks() {
        let document = TextEditorDocument()
        document.insertCards([music, contact])
        let lines = document.text.components(separatedBy: "\n")
        #expect(lines.count == 3 && lines[1].isEmpty)
        #expect(lines[0].hasPrefix("![Abbey Road](mural-card:") && lines[2].hasPrefix("![Fulana de Tal](mural-card:"))
        #expect(document.embeds.count == 2)
        for line in [lines[0], lines[2]] {
            let id = NoteImageMarkup.cardID(inSource: String(MarkdownImageSource.source(of: line)))
            #expect(id.flatMap { document.embeds[$0] } != nil)
        }
    }

    @Test("Com texto em volta, o bloco ganha uma linha em branco de cada lado")
    func insertBlocksBetweenText() {
        let document = TextEditorDocument()
        document.text = "antes depois"
        let middle = document.text.index(document.text.startIndex, offsetBy: 6)
        document.selection = middle..<middle
        document.insertCards([music])
        #expect(document.text.hasPrefix("antes \n\n![Abbey Road](mural-card:"))
        #expect(document.text.hasSuffix(")\n\ndepois"))
    }

    @Test("Imagens entram como linha provisória e ficam só na memória")
    func insertImages() {
        let document = TextEditorDocument()
        document.insertImages([.data(Data([1, 2, 3]), fileExtension: "png")])
        #expect(document.images.count == 1)
        let token = document.images.keys.first!
        #expect(document.text == NoteImageMarkup.pendingLine(token: token))
        #expect(document.hasImages && !document.hasEmbeds)
    }

    @Test("Texto entra no lugar da seleção")
    func insertTextAtSelection() {
        let document = TextEditorDocument()
        document.text = "um dois tres"
        let range = document.text.range(of: "dois")!
        document.selection = range
        document.insertText("2")
        #expect(document.text == "um 2 tres")
    }

    @Test("A formatação vale para a seleção e, sem seleção, para o texto todo")
    func applyFormat() {
        let document = TextEditorDocument()
        document.text = "ola mundo\noutra linha"
        document.selection = document.text.range(of: "mundo")
        document.applyFormat(.uppercase, locale: Locale(identifier: "pt_BR"))
        #expect(document.text == "ola MUNDO\noutra linha")
        document.selection = nil
        document.applyFormat(.uppercase, locale: Locale(identifier: "pt_BR"))
        #expect(document.text == "OLA MUNDO\nOUTRA LINHA")
    }

    @Test("A sugestão espera a pausa na digitação e veta post-it e lista com cartões ou imagens")
    func suggestionIsDebouncedAndVetoed() async throws {
        let document = TextEditorDocument(suggestionDelay: .milliseconds(40))
        document.text = "- a\n- b"
        #expect(document.suggestion.options.isEmpty, "a sugestão ainda não foi recalculada")
        try await settle { document.suggestion.suggested == .checklist }
        #expect(document.suggestion.suggested == .checklist)

        document.insertCards([music])
        try await settle { document.suggestion.unavailable[.checklist] != nil }
        #expect(document.suggestion.suggested == .text)
        #expect(document.suggestion.unavailable[.checklist] != nil && document.suggestion.unavailable[.sticky] != nil)
    }

    @Test("Só a última de várias mudanças seguidas é calculada")
    func suggestionKeepsOnlyTheLastChange() async throws {
        let document = TextEditorDocument(suggestionDelay: .milliseconds(40))
        for text in ["a", "- a\n- b", "Ligar para o marceneiro"] { document.text = text }
        try await settle { document.suggestion.suggested == .sticky }
        #expect(document.suggestion.suggested == .sticky)
    }

    // MARK: Formatação com cartões

    private func documentWithCard(_ text: (String, String) -> String) -> (document: TextEditorDocument, line: String) {
        let document = TextEditorDocument()
        let id = UUID()
        document.embeds[id] = music
        let line = NoteImageMarkup.cardLine(id: id, title: "Abbey Road")
        document.text = text(line, "")
        return (document, line)
    }

    @Test("Maiúsculas deixam a linha do cartão intacta e só mudam o texto")
    func uppercaseKeepsTheCardLine() {
        let (document, line) = documentWithCard { line, _ in "ola mundo\n\n\(line)\n\noutra linha" }
        document.selection = nil
        document.applyFormat(.uppercase, locale: Locale(identifier: "pt_BR"))
        #expect(document.text == "OLA MUNDO\n\n\(line)\n\nOUTRA LINHA")
    }

    @Test("Lista com marcadores nunca põe marcador na linha do cartão")
    func bulletListSkipsTheCardLine() {
        let (document, line) = documentWithCard { line, _ in "um\ndois\n\(line)\ntres" }
        document.applyFormat(.bulletList)
        #expect(document.text == "- um\n- dois\n\(line)\n- tres")
    }

    @Test("Juntar linhas não junta através da linha do cartão")
    func joinedLinesStopsAtTheCardLine() {
        let (document, line) = documentWithCard { line, _ in "a\nb\n\(line)\nc\nd" }
        document.applyFormat(.joinedLines)
        #expect(document.text == "a b\n\(line)\nc d")
    }

    @Test("Uma seleção que cobre o cartão formata só o texto de cada lado")
    func selectionSpanningACard() {
        let (document, line) = documentWithCard { line, _ in "ola\n\(line)\nmundo\nfora" }
        let start = document.text.startIndex
        let end = document.text.range(of: "mundo")!.upperBound
        document.selection = start..<end
        document.applyFormat(.uppercase, locale: Locale(identifier: "pt_BR"))
        #expect(document.text == "OLA\n\(line)\nMUNDO\nfora")
    }

    @Test("Colar de volta o texto copiado do editor religa as linhas dos cartões que o documento conhece")
    func pastingMarkdownLines() {
        let (document, line) = documentWithCard { line, _ in line }
        #expect(!document.paste(.text("só texto")))
        document.text = ""
        #expect(document.paste(.text(line)))
        #expect(document.text == line)
    }

    @Test("Negrito e itálico envolvem a seleção; uma seleção que toca a linha de um cartão não muda nada")
    func emphasis() {
        let document = TextEditorDocument()
        document.text = "ola mundo"
        document.selection = document.text.range(of: "mundo")
        document.applyEmphasis(.bold)
        #expect(document.text == "ola **mundo**")
        #expect(document.text[document.selection!] == "mundo")

        let (withCard, line) = documentWithCard { line, _ in "ola\n\(line)" }
        withCard.selection = withCard.text.startIndex..<withCard.text.endIndex
        withCard.applyEmphasis(.italic)
        #expect(withCard.text == "ola\n\(line)")
    }

    @Test("A contagem de palavras ignora as linhas de cartões e de imagens")
    func wordCount() {
        let document = TextEditorDocument()
        document.text = "uma duas  tres\n\nquatro"
        #expect(document.wordCount == 4)
        document.insertCards([music])
        #expect(document.wordCount == 4)
        #expect(!document.isEmpty)
        #expect(TextEditorDocument().isEmpty)
    }

    @Test("clear descarta o texto, os cartões e as imagens, inclusive os que já não eram citados")
    func clearDropsOrphans() {
        let document = TextEditorDocument()
        document.insertCards([music])
        document.insertImages([.data(Data([1]), fileExtension: "png")])
        document.text = "só texto"
        #expect(document.embeds.count == 1 && document.images.count == 1, "órfãos ficam durante a edição, para o ⌘Z")
        document.clear()
        #expect(document.text.isEmpty && document.embeds.isEmpty && document.images.isEmpty && document.selection == nil)
    }
}

/// O endereço de uma linha `![alt](origem)`.
private enum MarkdownImageSource {
    static func source(of line: String) -> String {
        guard let open = line.range(of: "](") else { return "" }
        return String(line[open.upperBound...].dropLast())
    }
}
