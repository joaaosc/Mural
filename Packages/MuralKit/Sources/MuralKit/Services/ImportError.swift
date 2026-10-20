import Foundation

/// Falhas ao transformar conteúdo colado ou arrastado em cartão.
public enum ImportError: Error, Equatable, Sendable {
    case fileNotFound(URL)
    case unsupportedType(String)
    case emptyText
}
