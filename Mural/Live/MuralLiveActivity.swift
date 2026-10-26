import Foundation
import GroupActivities
import MuralKit

/// A atividade do SharePlay do Live Share: só diz qual mural abrir e onde está o convite do iCloud. O conteúdo do mural não viaja
/// pela chamada; continua indo pelo iCloud.
nonisolated struct MuralLiveActivity: GroupActivity, Sendable, Equatable {
    static let activityIdentifier = "com.joaocosta.Mural.live-share"
    /// O título na chamada: neutro, sem o nome do mural (quem está na chamada pode não ter sido convidado para ele).
    static let title = "Mural ao vivo"

    let boardID: BoardID
    /// O endereço do convite do iCloud (`CKShare.url`), para quem foi convidado e ainda não aceitou; `nil` quando não se sabe.
    let shareURL: URL?

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = Self.title
        metadata.type = .createTogether
        return metadata
    }
}
