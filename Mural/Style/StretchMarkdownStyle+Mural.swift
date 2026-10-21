import StretchTextUI
import SwiftUI

extension StretchMarkdownStyle {
    /// Página de leitura da nota: corpo e títulos serifados, como o texto corrido do Mural.
    static let notePage = StretchMarkdownStyle(
        body: .system(.title3, design: .serif),
        headings: [
            .system(.title, design: .serif).bold(), .system(.title2, design: .serif).bold(),
            .system(.title3, design: .serif).bold(), .system(.headline, design: .serif),
        ],
        code: .system(.callout, design: .monospaced),
        blockSpacing: 14,
        indent: 22)

    /// Texto de abertura das listas, acima dos itens.
    static let checklistIntro = StretchMarkdownStyle(
        body: .body.weight(.medium),
        headings: [.headline],
        code: .callout.monospaced(),
        blockSpacing: 8,
        indent: 16)

    /// Miniatura do cartão: fontes fixas e pequenas, porque o cartão é uma
    /// miniatura da página, não texto para leitura.
    static let paperCard = StretchMarkdownStyle(
        body: .system(size: 5.5),
        headings: [.system(size: 7, weight: .semibold), .system(size: 6.5, weight: .semibold), .system(size: 6, weight: .semibold)],
        code: .system(size: 5.5, design: .monospaced),
        blockSpacing: 3,
        indent: 6)
}
