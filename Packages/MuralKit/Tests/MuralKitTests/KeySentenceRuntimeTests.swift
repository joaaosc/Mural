import Foundation
import FoundationModels
import StretchText
import Testing

@testable import MuralKit

/// Só roda quando pedido (`MURAL_RUNTIME_TESTS=1`) e com o modelo do aparelho
/// disponível. É evidência de que a cadeia inteira funciona neste Mac (idioma,
/// seletor, montagem e registro), não de que a frase escolhida é a melhor.
private let runtimeEnabled =
    ProcessInfo.processInfo.environment["MURAL_RUNTIME_TESTS"] == "1"
    && SystemLanguageModel.default.availability == .available

@MainActor
@Suite(
    "Modelo do aparelho no Mural (runtime real)",
    .enabled(if: runtimeEnabled, "defina MURAL_RUNTIME_TESTS=1 num Mac com o modelo disponível"),
    .serialized)
struct KeySentenceRuntimeTests {
    nonisolated static let notes = [
        "A design philosophy is a set of values that guides choices. Clarity before ornament. Light before furniture. Every object earns its place.",
        "A visita é na segunda de manhã. Medir a parede norte antes do meio-dia. Levar as amostras de tecido e o leque de cores.",
    ]

    @Test("O coordenador escolhe pelo modelo e entrega um registro válido para o texto", arguments: notes)
    func picksWithSystemModel(text: String) async throws {
        let id = UUID()
        var applied: KeySentenceRecord?
        let coordinator = KeySentenceCoordinator(source: { $0 == id ? text : nil }, apply: { applied = $1 })
        let started = ContinuousClock.now
        coordinator.enqueue(id)
        await coordinator.waitUntilIdle()
        let elapsed = ContinuousClock.now - started

        let record = try #require(applied)
        let choice = try #require(record.choices[0])
        print(
            "runtime \(KeySentenceCoordinator.dominantLocale(of: text).identifier): \(choice.source) frase \(choice.sentenceID) em \(elapsed)"
        )
        #expect(record.matches(text))
        #expect(choice.source == .model || choice.source == .cache)
        let result = NoteFolding.fold(text, record: record)
        #expect(result.document.expandedText == text)
        #expect(NoteFolding.notice(for: result) == nil)
    }
}
