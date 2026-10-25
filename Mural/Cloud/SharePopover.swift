import MuralKit
import MuralSync
import SwiftUI

/// O que o botão Compartilhar e o popover mostram de um mural: o papel da pessoa, quem tem acesso e o estado da sincronização.
/// Função pura dos fatos do mural, sem interface.
nonisolated struct ShareDisplay: Equatable {
    /// O papel da pessoa no mural.
    enum Role: Equatable {
        /// Mural só deste Mac.
        case local
        /// Mural da própria pessoa no iCloud (banco privado): ela convida e pode tirá-lo do iCloud.
        case owner
        /// Mural recebido por convite. `ownerName` é quem compartilhou, se o iCloud disse; `canEdit` é o que o convite permite.
        case guest(ownerName: String?, canEdit: Bool)
    }

    /// Uma pessoa convidada, como a lista do popover a mostra.
    struct Participant: Identifiable, Equatable {
        var id: String
        var name: String
        /// "pode editar", "só vê" ou "convite pendente".
        var detail: String

        init(_ participant: ShareSummary.Participant, index: Int) {
            id = participant.userRecordName ?? "participante-\(index)"
            name = participant.displayName ?? "Convidado"
            detail = participant.isAccepted ? (participant.permission == .readOnly ? "só vê" : "pode editar") : "convite pendente"
        }
    }

    var boardName: String
    var role: Role
    /// Quem foi convidado. Só o dono tem a lista; o convidado e o mural local ficam com ela vazia.
    var participants: [Participant]
    var status: SyncStatusDisplay
    var accountAvailable: Bool

    /// - Parameters:
    ///   - boardName: o nome do mural.
    ///   - cloud: o `cloud` do manifesto; `nil` num mural só deste Mac.
    ///   - share: o convite do mural em `CloudSyncController.shareStates`.
    ///   - issue: o aviso do mural em `CloudSyncController.issues`.
    ///   - isSending: o mural está em `CloudSyncController.sendingBoards`.
    ///   - accountAvailable: `CloudSyncController.accountAvailable`.
    init(
        boardName: String, cloud: BoardCloudInfo?, share: ShareSummary?, issue: SyncIssue?, isSending: Bool, accountAvailable: Bool
    ) {
        self.boardName = boardName
        self.accountAvailable = accountAvailable
        status = SyncStatusDisplay(issue: issue, isInCloud: cloud != nil, isSending: isSending, accountAvailable: accountAvailable)
        var role = Role.local
        var participants: [Participant] = []
        if let cloud {
            switch cloud.database {
            case .private:
                role = .owner
                participants = (share?.participants ?? []).enumerated().map { Participant($0.element, index: $0.offset) }
            case .shared:
                role = .guest(ownerName: cloud.ownerDisplayName ?? share?.ownerDisplayName, canEdit: !cloud.isReadOnly)
            }
        }
        self.role = role
        self.participants = participants
    }

    /// O mural está compartilhado: foi recebido por convite, ou o convite tem ao menos uma pessoa (aceita ou pendente).
    var isShared: Bool {
        switch role {
        case .local: false
        case .owner: !participants.isEmpty
        case .guest: true
        }
    }

    /// O símbolo do botão da barra: duas pessoas quando o mural é compartilhado, e o convite quando ainda não.
    var buttonSymbolName: String {
        isShared ? "person.2.fill" : "person.crop.circle.badge.plus"
    }

    /// O rótulo de acessibilidade do botão: o mural e o estado da sincronização.
    var accessibilityLabel: String {
        "Compartilhar \(boardName), \(status.text)"
    }
}

/// O popover do botão Compartilhar: o estado da sincronização, quem tem acesso e as ações do papel da pessoa no mural.
struct SharePopover: View {
    let display: ShareDisplay
    var onRemoveFromICloud: () -> Void = {}
    var onLeave: () -> Void = {}
    /// **Só do iCloud falso dos testes** (`CloudSyncController.inviteTestGuest(to:)`): `nil` com o iCloud de verdade, e o botão
    /// "Convidar convidado de teste" não aparece. É o caminho dos testes de interface até um mural compartilhado.
    var onInviteTestGuest: (() async throws -> Void)?

    @State private var isInvitingTestGuest = false
    @State private var inviteFailure: String?

    private var isOwner: Bool { display.role == .owner }

    private var isGuest: Bool {
        if case .guest = display.role { true } else { false }
    }

    // As ações falam com o iCloud: sem conta, o popover só explica.
    private var showsRemoveFromICloud: Bool { display.accountAvailable && isOwner }
    private var showsLeave: Bool { display.accountAvailable && isGuest }
    private var showsTestInvite: Bool { display.accountAvailable && !isGuest && onInviteTestGuest != nil }
    private var hasActions: Bool { showsRemoveFromICloud || showsLeave || showsTestInvite }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compartilhar “\(display.boardName)”")
                .font(.headline)
                .lineLimit(2)
            statusLine
            Divider()
            access
            if hasActions {
                Divider()
                actions
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share-popover")
    }

    private var statusLine: some View {
        Label(display.status.text, systemImage: display.status.symbolName)
            .font(.callout)
            .foregroundStyle(display.status.isWarning ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("share-status")
    }

    /// Quem tem acesso: para o dono, a lista de convidados (ou só ele); para quem recebeu o convite, de quem veio e o que pode fazer.
    @ViewBuilder
    private var access: some View {
        switch display.role {
        case .guest(let ownerName, let canEdit):
            VStack(alignment: .leading, spacing: 4) {
                Text(ownerName.map { "Compartilhado por \($0)" } ?? "Compartilhado com você")
                Text(canEdit ? "Você pode editar" : "Você só pode ver")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .accessibilityIdentifier("share-access")
        case .local, .owner:
            if display.participants.isEmpty {
                Text("Só você tem acesso")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("share-access")
            } else {
                VStack(spacing: 6) {
                    ForEach(display.participants) { participant in
                        HStack(alignment: .firstTextBaseline) {
                            Text(participant.name)
                            Spacer(minLength: 12)
                            Text(participant.detail)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("share-participant")
                    }
                }
                .font(.callout)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            // Lugar de "Convidar pessoas…" (próximo commit) e de "Live Share…" (commit seguinte): só ganham botão quando funcionarem.
            if showsTestInvite {
                Button(action: inviteTestGuest) {
                    Text("Convidar convidado de teste")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isInvitingTestGuest)
                .accessibilityIdentifier("share-invite-test-guest-button")
                if let inviteFailure {
                    Text(inviteFailure)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsRemoveFromICloud {
                Button(action: onRemoveFromICloud) {
                    Text("Tirar do iCloud…")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("share-remove-from-icloud-button")
            }
            if showsLeave {
                Button(role: .destructive, action: onLeave) {
                    Text("Sair do mural compartilhado…")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("share-leave-button")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func inviteTestGuest() {
        guard let onInviteTestGuest else { return }
        isInvitingTestGuest = true
        inviteFailure = nil
        Task {
            do {
                try await onInviteTestGuest()
            } catch {
                inviteFailure = error.localizedDescription
            }
            isInvitingTestGuest = false
        }
    }
}

// MARK: Previews

#Preview("Popover", traits: .fixedLayout(width: 1040, height: 340)) {
    SharePopoverGallery()
}

#Preview("Popover (escuro)", traits: .fixedLayout(width: 1040, height: 340)) {
    SharePopoverGallery()
        .preferredColorScheme(.dark)
}

/// O popover como o dono (mural compartilhado), o convidado que só vê e quem está sem conta do iCloud, lado a lado.
private struct SharePopoverGallery: View {
    private static let zone = CloudZoneID(name: "mural-de-exemplo")

    private let ownerShared = ShareDisplay(
        boardName: "Viagem a Lisboa",
        cloud: BoardCloudInfo(
            database: .private, zoneName: SharePopoverGallery.zone.name, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner),
        share: ShareSummary(
            zone: SharePopoverGallery.zone, currentUserPermission: .owner,
            participants: [
                .init(displayName: "Bia Souza", userRecordName: "bia", permission: .readWrite, isAccepted: true),
                .init(displayName: "Caio", userRecordName: "caio", permission: .readOnly, isAccepted: true),
                .init(displayName: nil, userRecordName: "pendente", permission: .readWrite, isAccepted: false),
            ]),
        issue: nil, isSending: false, accountAvailable: true)

    private let guestReadOnly = ShareDisplay(
        boardName: "Receitas da família",
        cloud: BoardCloudInfo(
            database: .shared, zoneName: SharePopoverGallery.zone.name, zoneOwnerName: "dono", ownerDisplayName: "Ana Lima",
            permission: .readOnly),
        share: nil, issue: .readOnly, isSending: false, accountAvailable: true)

    private let withoutAccount = ShareDisplay(
        boardName: "Ideias soltas", cloud: nil, share: nil, issue: nil, isSending: false, accountAvailable: false)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach([ownerShared, guestReadOnly, withoutAccount], id: \.boardName) { display in
                SharePopover(display: display)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}
