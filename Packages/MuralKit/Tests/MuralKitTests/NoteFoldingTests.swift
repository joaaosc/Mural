import Foundation
import StretchText
import Testing

@testable import MuralKit

@Suite("Dobra das notas")
struct NoteFoldingTests {
    static let body = "A visita é na segunda. Medir a parede norte.\n\nUma frase só."

    static let firstID = StretchID(path: [0])!

    /// Escolha da segunda frase do primeiro bloco, como se viesse do modelo.
    static func modelRecord(for source: String = body) -> KeySentenceRecord {
        KeySentenceRecord(
            source: source, choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 1), source: .model)])
    }

    @Test("Só o corpo da nota e a abertura da lista dobram; post-it, imagem e pasta não")
    func foldableSources() {
        #expect(NoteFolding.source(of: BoardItem(kind: .text, title: "T", text: Self.body)) == Self.body)
        let list = BoardItem(kind: .checklist, title: "L", checklist: ChecklistDocument(title: "L", intro: "Abre. Fecha.", sections: []))
        #expect(NoteFolding.source(of: list) == "Abre. Fecha.")
        #expect(NoteFolding.source(of: BoardItem(kind: .sticky, title: "S", text: Self.body)) == nil)
        #expect(NoteFolding.source(of: BoardItem(kind: .image, title: "I", text: Self.body)) == nil)
        #expect(NoteFolding.source(of: BoardItem(kind: .text, title: "T", text: "  \n ")) == nil)
        #expect(NoteFolding.fold(for: BoardItem(kind: .folder, title: "P")) == nil)
    }

    @Test("Sem escolhas guardadas, dobra pela primeira frase")
    func firstSentenceWithoutRecord() throws {
        let result = NoteFolding.fold(Self.body, record: nil)
        let stretch = try #require(result.document.stretch(at: Self.firstID))
        #expect(stretch.shortText == "A visita é na segunda.")
        #expect(result.document.expandedText == Self.body)
    }

    @Test("Escolha guardada e válida vira a frase curta")
    func appliesRecord() throws {
        let result = NoteFolding.fold(Self.body, record: Self.modelRecord())
        let stretch = try #require(result.document.stretch(at: Self.firstID))
        #expect(stretch.shortText == "Medir a parede norte.")
    }

    @Test("Escolha de um texto antigo é ignorada")
    func ignoresStaleRecord() throws {
        let edited = Self.body + "\n\nNovo parágrafo. Com duas frases."
        let result = NoteFolding.fold(edited, record: Self.modelRecord())
        #expect(try #require(result.document.stretch(at: Self.firstID)).shortText == "A visita é na segunda.")
        #expect(!Self.modelRecord().matches(edited))
    }

    @Test("Escolha que não cabe no texto (bloco ou frase inexistente) cai na primeira frase")
    func invalidChoiceFallsBack() throws {
        let bad = KeySentenceRecord(
            source: Self.body, choices: [2: SentenceChoice(sentenceID: SentenceID(segment: 2, index: 0), source: .model)])
        let result = NoteFolding.fold(Self.body, record: bad)
        #expect(try #require(result.document.stretch(at: Self.firstID)).shortText == "A visita é na segunda.")
    }

    @Test("Versão diferente do segmentador invalida as escolhas")
    func segmenterVersion() {
        let old = KeySentenceRecord(source: Self.body, choices: [:], segmenterVersion: TextSegmenter.version + 1)
        #expect(!old.matches(Self.body))
    }

    @Test("Registro guarda escolhas e falhas de uma montagem e volta igual")
    func recordFromFold() throws {
        let failure = KeySentenceFailure.modelUnavailable(.appleIntelligenceNotEnabled)
        let segmentation = TextSegmenter.segment(Self.body)
        let fold = try StretchFolder.fold(
            segmentation,
            choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 0), source: .firstSentenceAfterFailure(failure))])
        let record = KeySentenceRecord(source: Self.body, fold: fold)
        #expect(record.choices.count == 1)
        #expect(record.needsRetry)
        let decoded = try JSONDecoder().decode(KeySentenceRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    @Test(
        "Só falhas passageiras pedem nova tentativa",
        arguments: [
            (KeySentenceFailure.modelUnavailable(.modelNotReady), true), (.rateLimited, true), (.deadlineExceeded, true),
            (.unsupportedLocale("xx"), false), (.refusal, false), (.contextSizeExceeded(tokenCount: 9, contextSize: 4), false),
        ])
    func retryPolicy(failure: KeySentenceFailure, retries: Bool) {
        let record = KeySentenceRecord(
            source: Self.body,
            choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 0), source: .firstSentenceAfterFailure(failure))])
        #expect(record.needsRetry == retries)
    }

    @Test("Precisa de escolhas: texto dobrável sem registro, registro velho ou falha passageira")
    func needsChoices() {
        var item = BoardItem(kind: .text, title: "T", text: Self.body)
        #expect(NoteFolding.needsChoices(item))
        item.keySentences = Self.modelRecord()
        #expect(!NoteFolding.needsChoices(item))
        item.text = Self.body + " Mais uma."
        #expect(NoteFolding.needsChoices(item))
        #expect(!NoteFolding.needsChoices(BoardItem(kind: .text, title: "T", text: "Uma frase só.")))
        #expect(!NoteFolding.needsChoices(BoardItem(kind: .sticky, title: "S", text: Self.body)))
    }

    @Test("Aviso só aparece quando a primeira frase entrou por falha")
    func notice() {
        #expect(NoteFolding.notice(for: NoteFolding.fold(Self.body, record: nil)) == nil)
        #expect(NoteFolding.notice(for: NoteFolding.fold(Self.body, record: Self.modelRecord())) == nil)
        let failed = KeySentenceRecord(
            source: Self.body,
            choices: [
                0: SentenceChoice(
                    sentenceID: SentenceID(segment: 0, index: 0),
                    source: .firstSentenceAfterFailure(.modelUnavailable(.appleIntelligenceNotEnabled)))
            ])
        #expect(
            NoteFolding.notice(for: NoteFolding.fold(Self.body, record: failed))
                == "Frases curtas pela primeira frase: a Apple Intelligence está desligada.")
    }

    @Test("Cartão salvo antes do campo novo continua abrindo")
    func decodesOldItems() throws {
        let item = BoardItem(kind: .text, title: "Antiga", text: Self.body)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        json.removeValue(forKey: "keySentences")
        let decoded = try JSONDecoder().decode(BoardItem.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.keySentences == nil)
        #expect(decoded.text == Self.body)

        var withRecord = item
        withRecord.keySentences = Self.modelRecord()
        #expect(try JSONDecoder().decode(BoardItem.self, from: JSONEncoder().encode(withRecord)) == withRecord)
    }
}
