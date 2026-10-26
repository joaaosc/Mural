import CloudKit
import MuralKit
import MuralSync

/// O que o app faz com um convite do iCloud que o sistema entregou (a pessoa abriu o link). Função pura dos fatos do convite, sem
/// rede nem conta: todos os caminhos se testam sem o CloudKit de verdade.
nonisolated enum ShareAcceptance {
    /// Por que o convite não vale para o Mural.
    enum Rejection: Equatable {
        /// O convite é de outro app (outro container do iCloud).
        case otherContainer
        /// O convite é de um registro, e não de uma zona inteira: o Mural só compartilha murais inteiros.
        case notAZoneShare
        /// A zona do convite não é de um mural (`mural-<UUID>`).
        case notABoardZone
        /// Quem compartilhou tirou esta pessoa do mural.
        case accessRemoved

        /// O texto do aviso para a pessoa.
        var message: String {
            switch self {
            case .otherContainer, .notAZoneShare, .notABoardZone: "Este convite não é de um mural do Mural."
            case .accessRemoved: "Quem compartilhou este mural tirou o seu acesso a ele."
            }
        }
    }

    /// O que fazer com o convite.
    enum Decision: Equatable {
        /// O convite não vale: a pessoa recebe o aviso com o motivo.
        case reject(Rejection)
        /// A dona do mural abriu o próprio link: só abre o mural.
        case openOwn(BoardID)
        /// O convite já foi aceito (em outro Mac da pessoa): falta adotar o mural neste Mac.
        case adoptOnly(BoardID)
        /// Convite novo: aceita no iCloud e adota o mural neste Mac.
        case acceptAndAdopt(BoardID)
    }

    /// - Parameters:
    ///   - container: o container do iCloud a que o convite pertence.
    ///   - appContainer: o container do Mural.
    ///   - isZoneWide: o convite é de uma zona inteira (o registro dele é `CKRecordNameZoneWideShare`).
    ///   - zoneName: o nome da zona do convite.
    ///   - role: o papel desta pessoa no convite.
    ///   - status: se esta pessoa já aceitou o convite.
    static func decide(
        container: String, appContainer: String, isZoneWide: Bool, zoneName: String,
        role: CKShare.ParticipantRole, status: CKShare.ParticipantAcceptanceStatus
    ) -> Decision {
        guard container == appContainer else { return .reject(.otherContainer) }
        guard isZoneWide else { return .reject(.notAZoneShare) }
        guard let id = CloudSchema.boardID(fromZoneName: zoneName) else { return .reject(.notABoardZone) }
        if role == .owner { return .openOwn(id) }
        switch status {
        case .accepted: return .adoptOnly(id)
        case .removed: return .reject(.accessRemoved)
        // Convite novo. Um status que esta build não conhece também tenta aceitar: se o iCloud recusar, a pessoa recebe o erro.
        case .pending, .unknown: return .acceptAndAdopt(id)
        @unknown default: return .acceptAndAdopt(id)
        }
    }

    /// O `cloud` do mural recebido por este convite, como o coordenador do banco compartilhado o adota. Sem permissão de edição
    /// conhecida vale o menos que se pode dar: só ver. A permissão exata chega depois, com o convite buscado.
    static func cloudInfo(zone: CloudZoneID, ownerName: String?, permission: CKShare.ParticipantPermission) -> BoardCloudInfo {
        BoardCloudInfo(
            database: .shared, zoneName: zone.name, zoneOwnerName: zone.ownerName, ownerDisplayName: ownerName,
            permission: permission == .readWrite ? .readWrite : .readOnly)
    }
}
