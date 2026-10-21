import CryptoKit
import Foundation
import StretchText

/// Frases curtas escolhidas para um texto, guardadas no cartão para que o modelo
/// só seja consultado de novo quando o texto mudar.
///
/// Vale apenas para o texto de origem exato (pelo hash) e para a mesma versão do
/// segmentador; fora disso, quem lê volta para a primeira frase.
public struct KeySentenceRecord: Codable, Hashable, Sendable {
    /// SHA-256 do texto de origem, em hexadecimal.
    public var sourceHash: String
    public var segmenterVersion: Int
    /// Escolha de cada bloco dobrado, pelo índice do bloco.
    public var choices: [Int: SentenceChoice]
    /// Blocos que ficaram sem dobrar porque a escolha falhou.
    public var failures: [Int: KeySentenceFailure]

    public init(
        source: String,
        choices: [Int: SentenceChoice],
        failures: [Int: KeySentenceFailure] = [:],
        segmenterVersion: Int = TextSegmenter.version
    ) {
        self.sourceHash = Self.hash(of: source)
        self.segmenterVersion = segmenterVersion
        self.choices = choices
        self.failures = failures
    }

    /// Guarda as escolhas e as falhas de uma montagem já feita para `source`.
    public init(source: String, fold: FoldResult) {
        var choices: [Int: SentenceChoice] = [:]
        var failures: [Int: KeySentenceFailure] = [:]
        for decision in fold.decisions {
            switch decision {
            case .folded(let segment, _, let choice):
                choices[segment] = choice
            case .unchanged(let segment, .selectionFailed(let failure)):
                failures[segment] = failure
            case .unchanged:
                break
            }
        }
        self.init(source: source, choices: choices, failures: failures)
    }

    /// `true` quando as escolhas valem para este texto e este segmentador.
    public func matches(_ source: String) -> Bool {
        segmenterVersion == TextSegmenter.version && sourceHash == Self.hash(of: source)
    }

    /// Alguma escolha caiu na primeira frase por um motivo que pode passar
    /// (modelo indisponível, ocupado, sem tempo). Vale tentar de novo depois.
    public var needsRetry: Bool {
        let sources = choices.values.map(\.source)
        let failed = sources.compactMap { source -> KeySentenceFailure? in
            if case .firstSentenceAfterFailure(let failure) = source { return failure }
            return nil
        }
        return (failed + failures.values).contains(where: \.isTransient)
    }

    public static func hash(of source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension KeySentenceFailure {
    /// Falha que depende do momento, não do texto: outra tentativa pode dar certo.
    public var isTransient: Bool {
        switch self {
        case .modelUnavailable, .rateLimited, .modelTimeout, .deadlineExceeded, .cancelled, .concurrentRequests:
            true
        case .unsupportedLocale, .contextSizeExceeded, .tooManySentences, .guardrailViolation, .refusal,
            .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
            .transcriptMutationWhileResponding, .unparseableOutput, .invalidChoice, .invalidDecision, .unexpectedError:
            false
        }
    }

    /// Motivo em português, para o aviso discreto da nota.
    public var reason: String {
        switch self {
        case .modelUnavailable(.appleIntelligenceNotEnabled): "a Apple Intelligence está desligada"
        case .modelUnavailable(.deviceNotEligible): "este Mac não tem o modelo"
        case .modelUnavailable(.modelNotReady), .modelUnavailable(.assetsUnavailable): "o modelo ainda está sendo preparado"
        case .modelUnavailable(.unknown): "o modelo não está disponível"
        case .unsupportedLocale: "o idioma do texto não é atendido"
        case .contextSizeExceeded, .tooManySentences: "o parágrafo é grande demais"
        case .modelTimeout, .deadlineExceeded: "o modelo demorou demais"
        case .rateLimited, .concurrentRequests: "o modelo está ocupado"
        case .guardrailViolation, .refusal: "o modelo recusou o texto"
        case .cancelled: "a escolha foi interrompida"
        case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
            .transcriptMutationWhileResponding, .unparseableOutput, .invalidChoice, .invalidDecision, .unexpectedError:
            "erro inesperado do modelo"
        }
    }
}
