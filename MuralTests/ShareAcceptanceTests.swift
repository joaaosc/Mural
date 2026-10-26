import CloudKit
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// O que o app faz com cada convite do iCloud que o sistema entrega. A decisão é uma função pura: o aceite de verdade (o
/// `CKShare.Metadata` do sistema, o `accept` do container) só se confere com duas contas do iCloud.
@Suite("Convite do iCloud: o que fazer com o convite recebido")
struct ShareAcceptanceTests {
    private static let appContainer = "iCloud.com.joaocosta.Mural"
    private let board = BoardID()

    /// A decisão para um convite que, por padrão, é novo, de zona inteira e de um mural do Mural.
    private func decide(
        container: String = ShareAcceptanceTests.appContainer, isZoneWide: Bool = true, zoneName: String? = nil,
        role: CKShare.ParticipantRole = .privateUser, status: CKShare.ParticipantAcceptanceStatus = .pending
    ) -> ShareAcceptance.Decision {
        ShareAcceptance.decide(
            container: container, appContainer: Self.appContainer, isZoneWide: isZoneWide,
            zoneName: zoneName ?? CloudSchema.zoneName(for: board), role: role, status: status)
    }

    @Test("Convite de outro app, de um registro ou de uma zona que não é de mural é recusado, nesta ordem, com o aviso do Mural")
    func invitationsThatAreNotForTheMuralAreRejected() {
        #expect(decide(container: "iCloud.com.outro.App") == .reject(.otherContainer))
        #expect(decide(isZoneWide: false) == .reject(.notAZoneShare))
        #expect(decide(zoneName: "Outra") == .reject(.notABoardZone))
        let lowercased = CloudSchema.zoneName(for: board).lowercased()
        #expect(decide(zoneName: lowercased) == .reject(.notABoardZone), "o UUID tem de vir como foi gravado")

        // Mais de um defeito: vale o primeiro da lista, mesmo para a dona do mural.
        #expect(decide(container: "iCloud.com.outro.App", isZoneWide: false, zoneName: "Outra", role: .owner) == .reject(.otherContainer))
        #expect(decide(isZoneWide: false, zoneName: "Outra", role: .owner) == .reject(.notAZoneShare))
        #expect(decide(zoneName: "Outra", role: .owner) == .reject(.notABoardZone))

        let notForTheMural: [ShareAcceptance.Rejection] = [.otherContainer, .notAZoneShare, .notABoardZone]
        for rejection in notForTheMural {
            #expect(rejection.message == "Este convite não é de um mural do Mural.")
        }
    }

    @Test("A dona do mural que abre o próprio link só abre o mural, qualquer que seja o status")
    func theOwnerOpensTheOwnBoard() {
        for status in [CKShare.ParticipantAcceptanceStatus.accepted, .pending, .unknown] {
            #expect(decide(role: .owner, status: status) == .openOwn(board))
        }
    }

    @Test("Quem recebeu o convite: o novo é aceito e adotado, o já aceito em outro Mac só é adotado, e o removido é recusado")
    func guestsAcceptAdoptOrAreRejected() {
        for role in [CKShare.ParticipantRole.privateUser, .publicUser, .unknown] {
            #expect(decide(role: role, status: .pending) == .acceptAndAdopt(board))
            #expect(decide(role: role, status: .unknown) == .acceptAndAdopt(board), "status desconhecido tenta aceitar")
            #expect(decide(role: role, status: .accepted) == .adoptOnly(board))
            #expect(decide(role: role, status: .removed) == .reject(.accessRemoved))
        }
        #expect(ShareAcceptance.Rejection.accessRemoved.message == "Quem compartilhou este mural tirou o seu acesso a ele.")
    }

    @Test("O cloud do mural recebido: banco compartilhado, zona e dono do convite, e só editar quando o convite deixa")
    func cloudInfoOfAnInvitedBoard() {
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: board), ownerName: "_dono")

        let editor = ShareAcceptance.cloudInfo(zone: zone, ownerName: "Ana Lima", permission: .readWrite)
        #expect(
            editor
                == BoardCloudInfo(
                    database: .shared, zoneName: zone.name, zoneOwnerName: "_dono", ownerDisplayName: "Ana Lima", permission: .readWrite))

        for permission in [CKShare.ParticipantPermission.readOnly, .none, .unknown] {
            let info = ShareAcceptance.cloudInfo(zone: zone, ownerName: nil, permission: permission)
            #expect(info.permission == .readOnly, "sem permissão de edição conhecida vale só ver")
            #expect(info.ownerDisplayName == nil)
        }
    }
}
