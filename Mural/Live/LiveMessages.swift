import Foundation
import MuralKit

/// O cartão que a pessoa abriu: editando (nota ou post-it em edição) ou só vendo (página do cartão aberta).
nonisolated struct LiveFocus: Codable, Sendable, Equatable {
    var itemID: UUID
    var isEditing: Bool
}

/// Um elemento sendo arrastado e onde ele está agora: canto superior esquerdo, em pontos do mural (sem zoom).
nonisolated struct LiveDrag: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case item, freeText }
    var kind: Kind
    var id: UUID
    var x: Double
    var y: Double
}

/// Quem é a pessoa: mandado ao entrar (a todos) e a quem chega depois.
nonisolated struct LiveHello: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var version: Int = LiveHello.currentVersion
    var boardID: BoardID
    /// O `userRecordName` da pessoa no iCloud; quem recebe confere contra o convite do mural.
    var userRecordName: String?
    /// O nome que o Mac dela tem; só vale quando o convite não traz nome.
    var displayName: String?
    var focus: LiveFocus?
    /// Quem acabou de entrar pede que os outros respondam com o próprio `hello`.
    var replyRequested: Bool
}

/// Mensagens do canal confiável (chegam, e em ordem).
nonisolated enum LiveEvent: Codable, Sendable, Equatable {
    case hello(LiveHello)
    /// O Mac da pessoa acabou de enviar mudanças deste mural ao iCloud: quem recebe busca já.
    case saved(boardID: BoardID)
    case focus(boardID: BoardID, focus: LiveFocus?)
    /// Fim de um arrasto (o último movimento do canal sem garantia pode se perder).
    case dragEnded(boardID: BoardID)
    /// O ponteiro saiu do mural.
    case pointerLeft(boardID: BoardID)
    /// A pessoa saiu do Live Share.
    case bye
}

/// Mensagens do canal sem garantia: movimento, ~15 por segundo, só quando muda.
nonisolated enum LiveMotion: Codable, Sendable, Equatable {
    case pointer(boardID: BoardID, x: Double, y: Double)
    case drag(boardID: BoardID, drag: LiveDrag)
}
