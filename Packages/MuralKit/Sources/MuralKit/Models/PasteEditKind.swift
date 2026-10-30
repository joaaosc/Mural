import Foundation
import UniformTypeIdentifiers

/// Os tipos de conteúdo copiado que podem ser abertos num app para editar antes de colar.
///
/// É o ponto de extensão para novos tipos editáveis: cada caso diz em que formato o conteúdo vai para o arquivo
/// temporário e qual app o abre por padrão.
public enum PasteEditKind: String, CaseIterable, Sendable {
    case text
    case image
    case pdf

    /// O tipo editável de um conteúdo da área de transferência.
    /// - Returns: `nil` para o que não se edita fora do Mural: links, arquivos, música e área vazia.
    public init?(_ kind: ClipboardKind) {
        switch kind {
        case .text: self = .text
        case .image: self = .image
        case .pdf: self = .pdf
        case .nothing, .links, .files, .music: return nil
        }
    }

    /// O formato do arquivo temporário que o app de edição abre.
    public var contentType: UTType {
        switch self {
        case .text: .plainText
        case .image: .png
        case .pdf: .pdf
        }
    }

    /// A extensão do arquivo temporário, sem o ponto.
    public var fileExtension: String {
        switch self {
        case .text: "txt"
        case .image: "png"
        case .pdf: "pdf"
        }
    }

    /// O identificador do app que abre o arquivo por padrão (TextEdit ou Pré-Visualização).
    public var defaultEditorBundleIdentifier: String {
        switch self {
        case .text: "com.apple.TextEdit"
        case .image, .pdf: "com.apple.Preview"
        }
    }
}
