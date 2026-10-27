import Foundation
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// O que o botão Compartilhar e o popover mostram do estado do mural no iCloud.
struct SyncStatusIndicatorTests {
    /// Um mural no iCloud, com conta e sem envio em andamento, salvo o que o teste mudar.
    private func status(
        _ issue: SyncIssue? = nil, inCloud: Bool = true, sending: Bool = false, account: Bool = true
    ) -> SyncStatusDisplay {
        SyncStatusDisplay(issue: issue, isInCloud: inCloud, isSending: sending, accountAvailable: account)
    }

    @Test func withoutIssueShowsSynced() {
        let display = status()
        #expect(display.symbolName == "checkmark.icloud")
        #expect(display.text == "Sincronizado com o iCloud")
        #expect(!display.isWarning)
    }

    @Test func boardOnlyOnThisMacSaysSo() {
        let display = status(inCloud: false)
        #expect(display.symbolName == "icloud")
        #expect(display.text == "Só neste Mac")
        #expect(!display.isWarning)
    }

    @Test func sendingShowsTheUpload() {
        let display = status(sending: true)
        #expect(display.symbolName == "icloud.and.arrow.up")
        #expect(display.text == "Enviando ao iCloud…")
        #expect(!display.isWarning)
    }

    @Test func withoutAccountExplainsHowToShare() {
        let display = status(account: false)
        #expect(display.symbolName == "icloud.slash")
        #expect(display.text == "Entre no iCloud nos Ajustes do Sistema para compartilhar")
        #expect(display.isWarning, "mural no iCloud parado por falta de conta")
        #expect(!status(inCloud: false, account: false).isWarning, "mural só deste Mac não ganha selo de aviso")
    }

    @Test func quotaExceededWarnsAboutOwnersSpace() {
        let display = status(.quotaExceeded)
        #expect(display.symbolName == "exclamationmark.icloud")
        #expect(display.text == "Sem espaço no iCloud do dono do mural")
        #expect(display.isWarning)
    }

    @Test func awaitingFirstFetchIsInformativeNotAWarning() {
        let display = status(.awaitingFirstFetch)
        #expect(display.symbolName == "icloud.and.arrow.down")
        #expect(display.text == "Baixando do iCloud…")
        #expect(!display.isWarning)
    }

    @Test func readOnlyIsNotAWarning() {
        let display = status(.readOnly)
        #expect(display.symbolName == "icloud")
        #expect(display.text == "Você só pode ver este mural")
        #expect(!display.isWarning)
    }

    @Test(arguments: [
        SyncIssue.recordTooLarge(UUID()), .needsNewerApp, .localSaveFailed, .other("detalhe técnico"),
    ])
    func otherIssuesWarnWithOwnText(issue: SyncIssue) {
        let display = status(issue)
        #expect(display.symbolName == "exclamationmark.icloud")
        #expect(display.isWarning)
        #expect(!display.text.isEmpty)
        #expect(!display.text.contains("detalhe técnico"))
    }

    @Test func noAccountBeatsSendingAndIssuesAndSendingBeatsIssues() {
        #expect(status(.quotaExceeded, sending: true, account: false).symbolName == "icloud.slash")
        #expect(status(.quotaExceeded, sending: true).symbolName == "icloud.and.arrow.up")
        #expect(status(.quotaExceeded, inCloud: false).text == "Só neste Mac")
    }

    @Test func eachStateHasItsOwnText() {
        let issues: [SyncIssue?] = [
            nil, .quotaExceeded, .readOnly, .recordTooLarge(UUID()), .needsNewerApp, .localSaveFailed, .awaitingFirstFetch, .other("x"),
        ]
        let texts =
            issues.map { status($0).text } + [
                status(inCloud: false).text, status(sending: true).text, status(account: false).text,
            ]
        #expect(Set(texts).count == texts.count)
    }

    // MARK: O que o botão e o popover mostram

    private static let zone = CloudZoneID(name: "mural")

    private func owner() -> BoardCloudInfo {
        BoardCloudInfo(database: .private, zoneName: Self.zone.name, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
    }

    private func guest(_ permission: BoardCloudInfo.Permission, ownerName: String? = "Ana") -> BoardCloudInfo {
        BoardCloudInfo(
            database: .shared, zoneName: Self.zone.name, zoneOwnerName: "dono", ownerDisplayName: ownerName, permission: permission)
    }

    private func share(_ participants: [ShareSummary.Participant], ownerName: String? = nil) -> ShareSummary {
        ShareSummary(zone: Self.zone, ownerDisplayName: ownerName, participants: participants)
    }

    private func shareDisplay(
        cloud: BoardCloudInfo?, share: ShareSummary? = nil, issue: SyncIssue? = nil, account: Bool = true
    ) -> ShareDisplay {
        ShareDisplay(boardName: "Casa", cloud: cloud, share: share, issue: issue, isSending: false, accountAvailable: account)
    }

    @Test func ownerListsGuestsWithPermissionAndPendingInvitations() {
        let invited = share([
            .init(displayName: "Bia", userRecordName: "bia", permission: .readWrite, isAccepted: true),
            .init(displayName: "Caio", userRecordName: "caio", permission: .readOnly, isAccepted: true),
            .init(displayName: nil, userRecordName: nil, permission: .readWrite, isAccepted: false),
        ])

        let display = shareDisplay(cloud: owner(), share: invited)

        #expect(display.role == .owner)
        #expect(display.participants.map(\.name) == ["Bia", "Caio", "Convidado"])
        #expect(display.participants.map(\.detail) == ["pode editar", "só vê", "convite pendente"])
        #expect(Set(display.participants.map(\.id)).count == 3, "cada linha tem identidade própria")
        #expect(display.isShared)
        #expect(display.buttonSymbolName == "person.2.fill")
        #expect(display.accessibilityLabel == "Compartilhar Casa, Sincronizado com o iCloud")
    }

    @Test func ownerWithoutGuestsAndLocalBoardAreNotShared() {
        let noGuests = shareDisplay(cloud: owner(), share: share([]))
        let local = shareDisplay(cloud: nil)

        #expect(noGuests.role == .owner)
        #expect(local.role == .local)
        for display in [noGuests, local] {
            #expect(display.participants.isEmpty)
            #expect(!display.isShared)
            #expect(display.buttonSymbolName == "person.crop.circle.badge.plus")
        }
        #expect(local.status.text == "Só neste Mac")
    }

    @Test func guestIsSharedAndKnowsWhoSharedAndWhatItCanDo() {
        let editor = shareDisplay(cloud: guest(.readWrite))
        let viewer = shareDisplay(cloud: guest(.readOnly, ownerName: nil), share: share([], ownerName: "Ana"), issue: .readOnly)

        #expect(editor.role == .guest(ownerName: "Ana", canEdit: true))
        #expect(viewer.role == .guest(ownerName: "Ana", canEdit: false), "sem o nome no manifesto vale o do convite")
        #expect(editor.isShared && viewer.isShared)
        #expect(editor.participants.isEmpty)
        #expect(viewer.status.text == "Você só pode ver este mural")
    }
}
