import Foundation
import StretchText
import StretchTextGeneration
import Testing

@testable import MuralKit

/// Seletor falso: escolhe a última frase ou falha, e conta as consultas.
private actor FakePicker: KeySentencePicker {
    private let failure: KeySentenceFailure?
    private(set) var calls = 0

    init(failing failure: KeySentenceFailure? = nil) {
        self.failure = failure
    }

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        calls += 1
        if let failure { return .failed(failure) }
        guard let last = sentences.last else { return .noEligibleSentence }
        return .selected(sentenceID: last.id, source: .model)
    }
}

/// Seletor que espera a porta abrir antes de escolher a última frase.
private actor GatedPicker: KeySentencePicker {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var started = 0

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        started += 1
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard let last = sentences.last else { return .noEligibleSentence }
        return .selected(sentenceID: last.id, source: .model)
    }

    func waitUntilStarted(_ count: Int) async {
        while started < count { await Task.yield() }
    }
}

@MainActor
@Suite("Escolha das frases em segundo plano")
struct KeySentenceCoordinatorTests {
    static let text = "A visita é na segunda. Medir a parede norte."

    /// Textos por cartão e as entregas, na ordem.
    @MainActor
    final class Harness {
        var texts: [UUID: String] = [:]
        var applied: [(UUID, KeySentenceRecord)] = []

        func coordinator(_ picker: any KeySentencePicker) -> KeySentenceCoordinator {
            KeySentenceCoordinator(
                picker: picker, locale: { _ in Locale(identifier: "pt-BR") },
                source: { [unowned self] in self.texts[$0] },
                apply: { [unowned self] in self.applied.append(($0, $1)) })
        }
    }

    @Test("Escolhe com o modelo e entrega o registro do texto atual")
    func picksWithModel() async throws {
        let harness = Harness()
        let id = UUID()
        harness.texts[id] = Self.text
        let coordinator = harness.coordinator(FakePicker())
        coordinator.enqueue(id)
        await coordinator.waitUntilIdle()

        let (appliedID, record) = try #require(harness.applied.first)
        #expect(appliedID == id)
        #expect(record.matches(Self.text))
        #expect(record.choices[0] == SentenceChoice(sentenceID: SentenceID(segment: 0, index: 1), source: .model))
        #expect(coordinator.currentItemID == nil)
    }

    @Test("Falha vira primeira frase com motivo; o mesmo texto não é tentado de novo na sessão")
    func failureIsNotRetriedInLoop() async throws {
        let harness = Harness()
        let id = UUID()
        harness.texts[id] = Self.text
        let picker = FakePicker(failing: .modelUnavailable(.appleIntelligenceNotEnabled))
        let coordinator = harness.coordinator(picker)
        coordinator.enqueue(id)
        await coordinator.waitUntilIdle()

        let record = try #require(harness.applied.first?.1)
        #expect(record.choices[0]?.source == .firstSentenceAfterFailure(.modelUnavailable(.appleIntelligenceNotEnabled)))
        #expect(record.needsRetry)

        coordinator.enqueue(id)
        await coordinator.waitUntilIdle()
        #expect(await picker.calls == 1)

        harness.texts[id] = Self.text + " Levar as amostras."
        coordinator.enqueue(id)
        await coordinator.waitUntilIdle()
        #expect(await picker.calls == 2)
    }

    @Test("O cartão aberto passa à frente da fila")
    func priority() async {
        let harness = Harness()
        let (a, b, c) = (UUID(), UUID(), UUID())
        for id in [a, b, c] { harness.texts[id] = Self.text }
        let picker = GatedPicker()
        let coordinator = harness.coordinator(picker)
        coordinator.enqueue(a)
        coordinator.enqueue(b)
        await picker.waitUntilStarted(1)
        #expect(coordinator.currentItemID == a)
        coordinator.enqueue(c, first: true)
        await picker.open()
        await coordinator.waitUntilIdle()
        #expect(harness.applied.map(\.0) == [a, c, b])
    }

    @Test("Texto editado durante a escolha: a escolha velha não é guardada")
    func editDuringChoice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralCoordinator-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let note = try #require(model.importText(Self.text, as: .text))
        let picker = GatedPicker()
        let coordinator = KeySentenceCoordinator(
            picker: picker, locale: { _ in Locale(identifier: "pt-BR") },
            source: { model.item(id: $0).flatMap(NoteFolding.source(of:)) },
            apply: { model.setKeySentences($1, for: $0) })
        coordinator.enqueue(note.id)
        await picker.waitUntilStarted(1)
        model.updateNote(note.id, title: note.title, text: "Outro texto. Com duas frases.")
        await picker.open()
        await coordinator.waitUntilIdle()
        #expect(model.item(id: note.id)?.keySentences == nil)
    }

    @Test("Cancelar para tudo, nada é entregue, e o cartão pode ser tentado depois")
    func cancelAll() async {
        let harness = Harness()
        let (a, b) = (UUID(), UUID())
        harness.texts[a] = Self.text
        harness.texts[b] = Self.text
        let picker = GatedPicker()
        let coordinator = harness.coordinator(picker)
        coordinator.enqueue(a)
        coordinator.enqueue(b)
        await picker.waitUntilStarted(1)
        coordinator.cancelAll()
        await picker.open()
        await coordinator.waitUntilIdle()
        // Dá tempo de a tarefa cancelada terminar.
        for _ in 0..<50 { await Task.yield() }
        #expect(harness.applied.isEmpty)
        #expect(coordinator.currentItemID == nil)

        coordinator.enqueue(a)
        await coordinator.waitUntilIdle()
        #expect(harness.applied.map(\.0) == [a])
    }

    @Test("Cartão apagado ou sem texto dobrável é pulado")
    func skipsMissing() async {
        let harness = Harness()
        let picker = FakePicker()
        let coordinator = harness.coordinator(picker)
        coordinator.enqueue(UUID())
        await coordinator.waitUntilIdle()
        #expect(harness.applied.isEmpty)
        #expect(await picker.calls == 0)
    }

    @Test(
        "Idioma do texto pelo idioma predominante",
        arguments: [
            ("The quick brown fox jumps over the lazy dog near the river bank.", "en"),
            ("A visita é na segunda de manhã e precisamos medir a parede norte da sala.", "pt"),
        ])
    func dominantLocale(text: String, language: String) {
        #expect(KeySentenceCoordinator.dominantLocale(of: text).language.languageCode?.identifier == language)
    }
}
