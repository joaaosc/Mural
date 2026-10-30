import AppKit
import MuralKit

/// O anexo que ocupa o lugar de uma linha `![título](mural-card:<UUID>)` ou `![…](mural-colando:<TOKEN>)` no texto do editor.
///
/// Mostra o cartão (ou a imagem) como uma view dentro do texto (`NSTextAttachmentViewProvider`, só no TextKit 2) e guarda a linha
/// de Markdown de que veio, para o texto voltar a ser Markdown (`EditorAttachmentBridge`). Ocupa um caractere (U+FFFC).
nonisolated final class EmbeddedTextAttachment: NSTextAttachment {
    /// O que o anexo mostra.
    enum Content: Sendable {
        case card(EmbeddedCard, title: String)
        case image(NSImage?, alt: String)
    }

    /// Largura máxima do anexo, em pontos.
    static let maximumWidth: CGFloat = 320

    let markdownLine: String
    let content: Content
    /// A razão altura ÷ largura do que o anexo mostra, calculada ao criar.
    let heightRatio: CGFloat

    init(markdownLine: String, content: Content) {
        self.markdownLine = markdownLine
        self.content = content
        self.heightRatio = Self.heightRatio(of: content)
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = true
    }

    required init?(coder: NSCoder) {
        // Copiar o anexo para fora do editor não leva o cartão: ele volta como um anexo vazio.
        self.markdownLine = ""
        self.content = .image(nil, alt: "")
        self.heightRatio = 0.75
        super.init(coder: coder)
    }

    private static func heightRatio(of content: Content) -> CGFloat {
        switch content {
        case .card:
            return EmbeddedCardStrip.height / EmbeddedCardStrip.maximumWidth
        case .image(let image, _):
            guard let size = image?.size, size.width > 0, size.height > 0 else { return 0.75 }
            return min(size.height / size.width, 1.5)
        }
    }

    override func viewProvider(
        for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        EmbeddedAttachmentViewProvider(
            textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let available = proposedLineFragment.width > 1 ? proposedLineFragment.width : Self.maximumWidth
        let width = min(Self.maximumWidth, available)
        return CGRect(x: 0, y: 0, width: width, height: (width * heightRatio).rounded())
    }
}
