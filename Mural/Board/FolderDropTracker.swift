import Foundation

/// Decide em qual pasta o cartão arrastado seria guardado se fosse solto agora.
///
/// A pasta que já estava sob o ponteiro quando o arrasto começou (um post-it por cima de uma
/// pasta, por exemplo) só vira destino depois que o ponteiro sai dela uma vez: um empurrão no
/// post-it não deve guardá-lo na pasta de baixo.
struct FolderDropTracker: Equatable {
    /// Pasta sob o ponteiro no começo do arrasto, enquanto o ponteiro ainda não saiu dela.
    private(set) var startFolder: UUID?
    /// Pasta que receberia o cartão agora; `nil` quando soltar só reposiciona.
    private(set) var target: UUID?

    init(startFolder: UUID?) {
        self.startFolder = startFolder
    }

    /// Atualiza com a pasta sob o ponteiro agora (`nil` fora de qualquer pasta).
    mutating func update(folderUnderPointer folder: UUID?) {
        if startFolder != nil, folder != startFolder { startFolder = nil }
        target = folder == startFolder ? nil : folder
    }
}
