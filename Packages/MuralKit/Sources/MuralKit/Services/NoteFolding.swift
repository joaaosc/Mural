import Foundation
import StretchText

/// Dobra o texto dos cartões com o StretchText: cada parágrafo de duas frases ou
/// mais mostra só a frase curta até o leitor abri-lo.
///
/// Só o corpo das notas e a abertura das listas dobram; post-its, legendas e
/// títulos ficam como estão. Com escolhas guardadas e válidas para o texto
/// (``KeySentenceRecord``), a frase curta é a escolhida; sem elas, a primeira.
public enum NoteFolding {
    /// O texto dobrável do cartão, ou `nil` quando ele não dobra.
    public static func source(of item: BoardItem) -> String? {
        let source: String? =
            switch item.kind {
            case .text: item.text
            case .checklist: item.checklist?.intro
            case .image, .video, .pdf, .sticky, .folder, .link, .reminder: nil
            }
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return source
    }

    /// O texto do cartão dobrado, ou `nil` quando ele não tem texto dobrável.
    public static func fold(for item: BoardItem) -> FoldResult? {
        source(of: item).map { fold($0, record: item.keySentences) }
    }

    /// Reaplica as escolhas guardadas quando valem para `source`; senão, ou se
    /// alguma não couber mais no texto, dobra pela primeira frase.
    public static func fold(_ source: String, record: KeySentenceRecord?) -> FoldResult {
        let segmentation = TextSegmenter.segment(source)
        guard let record, record.matches(source),
            let result = try? StretchFolder.fold(segmentation, choices: record.choices, failures: record.failures)
        else { return StretchFolder.foldWithFirstSentence(segmentation) }
        return result
    }

    /// `true` quando o cartão tem texto dobrável sem escolhas válidas, ou com
    /// uma falha que pode passar: vale consultar o modelo.
    public static func needsChoices(_ item: BoardItem) -> Bool {
        guard let source = source(of: item) else { return false }
        guard let record = item.keySentences, record.matches(source) else {
            return TextSegmenter.segment(source).segments.contains(where: \.isFoldable)
        }
        return record.needsRetry
    }

    /// Aviso discreto quando alguma frase curta não veio do modelo por falha.
    /// `nil` quando tudo veio do modelo, do cache, de frase única, ou quando
    /// a escolha ainda não aconteceu.
    public static func notice(for result: FoldResult) -> String? {
        let failures = result.decisions.compactMap { decision -> KeySentenceFailure? in
            switch decision {
            case .folded(_, _, let choice):
                if case .firstSentenceAfterFailure(let failure) = choice.source { return failure }
                return nil
            case .unchanged(_, .selectionFailed(let failure)):
                return failure
            case .unchanged:
                return nil
            }
        }
        guard let first = failures.first else { return nil }
        return "Frases curtas pela primeira frase: \(first.reason)."
    }
}
