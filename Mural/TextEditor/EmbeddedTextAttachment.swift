import AppKit
import MuralKit

/// O anexo que ocupa o lugar de uma linha `![título](mural-card:<UUID>)` ou `![…](mural-colando:<TOKEN>)` no texto do editor.
///
/// É desenhado como imagem (`image(for:attributes:location:textContainer:)`), já pronta ao criar o anexo (`Picture`), e guarda a
/// linha de Markdown de que veio, para o texto voltar a ser Markdown (`EditorAttachmentBridge`). Ocupa um caractere (U+FFFC).
///
/// Nunca uma view (`NSTextAttachmentViewProvider`): o TextKit 2 cria uma nova a cada layout da linha e só a põe na tela numa passada
/// posterior. Enquanto isso o anexo some, com o ícone genérico de arquivo por um instante, e a linha muda de altura.
nonisolated final class EmbeddedTextAttachment: NSTextAttachment {
    /// O que o anexo mostra.
    enum Content: Sendable {
        case card(EmbeddedCard, title: String)
        case image(NSImage?, alt: String)
    }

    /// O desenho do anexo em cada aparência; a imagem colada é a mesma nas duas.
    struct Picture {
        let light: NSImage
        let dark: NSImage
    }

    /// Largura máxima do anexo, em pontos.
    static let maximumWidth: CGFloat = 320

    let markdownLine: String
    let content: Content
    /// A razão altura ÷ largura do que o anexo mostra, calculada ao criar.
    let heightRatio: CGFloat
    /// O desenho; `nil` só no anexo que voltou de um arquivo (`init(coder:)`), que não desenha nada.
    let picture: Picture?

    init(markdownLine: String, content: Content, picture: Picture?) {
        self.markdownLine = markdownLine
        self.content = content
        self.heightRatio = Self.heightRatio(of: content)
        self.picture = picture
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = false
    }

    required init?(coder: NSCoder) {
        // Copiar o anexo para fora do editor não leva o cartão: ele volta como um anexo vazio.
        self.markdownLine = ""
        self.content = .image(nil, alt: "")
        self.heightRatio = 0.75
        self.picture = nil
        super.init(coder: coder)
    }

    /// A razão altura ÷ largura de um conteúdo.
    static func heightRatio(of content: Content) -> CGFloat {
        switch content {
        case .card:
            return EmbeddedCardStrip.height / EmbeddedCardStrip.maximumWidth
        case .image(let image, _):
            guard let size = image?.size, size.width > 0, size.height > 0 else { return 0.75 }
            return min(size.height / size.width, 1.5)
        }
    }

    override func image(
        for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSImage? {
        guard let picture else { return NSImage(size: bounds.size) }
        return Self.isDark(textContainer) ? picture.dark : picture.light
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let available = proposedLineFragment.width > 1 ? proposedLineFragment.width : Self.maximumWidth
        let width = min(Self.maximumWidth, available)
        return CGRect(x: 0, y: 0, width: width, height: (width * heightRatio).rounded())
    }

    /// Precisa existir, mesmo sem nunca ser chamada: sem esta sobrescrita o TextKit 2 reserva a altura do anexo e não pede a imagem
    /// (`image(for:attributes:location:textContainer:)`), e a linha fica em branco (macOS 27.2).
    override func viewProvider(
        for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        nil
    }

    /// A aparência do campo; fora da thread principal, que o `NSTextView` não usa para desenhar, vale a clara.
    private static func isDark(_ textContainer: NSTextContainer?) -> Bool {
        guard Thread.isMainThread else { return false }
        nonisolated(unsafe) let container = textContainer
        return MainActor.assumeIsolated {
            container?.textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }
}
