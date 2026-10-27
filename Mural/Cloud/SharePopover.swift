import Foundation
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

/// O que a seção do Live Share do popover mostra: se dá para começar, se a pessoa está entrando ou quem está ao vivo. Função pura dos
/// fatos do controlador e do mural, sem interface.
nonisolated struct LiveShareDisplay: Equatable {
    /// Uma pessoa ao vivo, como a lista do popover a mostra.
    struct Person: Equatable, Identifiable {
        var id: UUID
        var name: String
        /// O lugar da pessoa na paleta (`LivePalette`).
        var colorIndex: Int
        /// "editando “título”", "vendo “título”" ou "no mural".
        var activity: String
    }

    enum State: Equatable {
        /// Por que não dá para começar agora.
        case unavailable(String)
        /// Dá para começar. `inCall`: há uma chamada do FaceTime em andamento, onde o Live Share começa direto.
        case ready(inCall: Bool)
        case connecting
        /// Ao vivo. `unverifiedCount`: quem está na sessão e não tem acesso a este mural (não entra na lista).
        case live(people: [Person], unverifiedCount: Int)
    }

    var state: State

    /// A seção do Live Share de um mural. Entrando ou ao vivo neste mural vale antes de tudo (quem está ao vivo precisa poder sair);
    /// depois, sem conta do iCloud, sem mural compartilhado e, por fim, pronto para começar. Um Live Share em outro mural não conta.
    /// - Parameters:
    ///   - phase: `LiveShareController.phase`.
    ///   - boardID: o mural do popover.
    ///   - peers: `LiveShareController.peers(on:)`, as pessoas conferidas deste mural.
    ///   - unverifiedCount: quantas pessoas da sessão não estão no convite do mural (`LivePresence.unverifiedCount`).
    ///   - isShared: `ShareDisplay.isShared`.
    ///   - accountAvailable: `CloudSyncController.accountAvailable`.
    ///   - isInCall: `LiveShareController.isInCall`.
    ///   - itemTitle: o título de um cartão deste mural; `nil` quando não está aqui.
    /// - Returns: `nil` quando a seção não aparece (sem conta do iCloud: o popover já explica).
    static func make(
        phase: LiveShareController.Phase, boardID: BoardID, peers: [LivePeer], unverifiedCount: Int, isShared: Bool,
        accountAvailable: Bool, isInCall: Bool, itemTitle: (UUID) -> String?
    ) -> LiveShareDisplay? {
        switch phase {
        case .connecting(let id) where id == boardID:
            return LiveShareDisplay(state: .connecting)
        case .live(let id) where id == boardID:
            let people = peers.map { peer in
                Person(
                    id: peer.id, name: peer.name, colorIndex: peer.colorIndex, activity: activity(of: peer.focus, itemTitle: itemTitle))
            }
            return LiveShareDisplay(state: .live(people: people, unverifiedCount: unverifiedCount))
        case .idle, .connecting, .live:
            break
        }
        guard accountAvailable else { return nil }
        guard isShared else { return LiveShareDisplay(state: .unavailable("Convide pessoas para usar o Live Share.")) }
        return LiveShareDisplay(state: .ready(inCall: isInCall))
    }

    /// O que a pessoa faz: o cartão aberto (com o título, quando este Mac o conhece) ou "no mural".
    private static func activity(of focus: LiveFocus?, itemTitle: (UUID) -> String?) -> String {
        guard let focus else { return "no mural" }
        let title = itemTitle(focus.itemID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let card = title.isEmpty ? "um cartão" : "“\(title)”"
        return "\(focus.isEditing ? "editando" : "vendo") \(card)"
    }
}

/// O popover do botão Compartilhar: o estado da sincronização, quem tem acesso e as ações do papel da pessoa no mural.
struct SharePopover: View {
    let display: ShareDisplay
    var onRemoveFromICloud: () -> Void = {}
    var onLeave: () -> Void = {}
    /// O mural a entregar ao compartilhamento do sistema, para o botão "Convidar pessoas…" (ou "Gerenciar pessoas…", quando o item já
    /// traz o convite). `nil` com o iCloud falso ou num mural que não pode ser convidado (o rascunho de exemplo): sem botão.
    var shareItem: BoardShareItem?
    /// **Só do iCloud falso dos testes** (`CloudSyncController.inviteTestGuest(to:)`): `nil` com o iCloud de verdade, e o botão
    /// "Convidar convidado de teste" não aparece. É o caminho dos testes de interface até um mural compartilhado.
    var onInviteTestGuest: (() async throws -> Void)?
    /// A seção do Live Share, entre quem tem acesso e as ações. `nil` esconde a seção (sem o controlador, ou sem conta do iCloud).
    var live: LiveShareDisplay?
    var onStartLive: () -> Void = {}
    var onLeaveLive: () -> Void = {}

    @State private var isInvitingTestGuest = false
    @State private var inviteFailure: String?

    private var isOwner: Bool { display.role == .owner }

    private var isGuest: Bool {
        if case .guest = display.role { true } else { false }
    }

    // As ações falam com o iCloud: sem conta, o popover só explica. Quem recebeu o convite não convida outras pessoas.
    private var showsInvite: Bool { display.accountAvailable && !isGuest && shareItem != nil }
    private var showsRemoveFromICloud: Bool { display.accountAvailable && isOwner }
    private var showsLeave: Bool { display.accountAvailable && isGuest }
    private var showsTestInvite: Bool { display.accountAvailable && !isGuest && onInviteTestGuest != nil }
    private var hasActions: Bool { showsInvite || showsRemoveFromICloud || showsLeave || showsTestInvite }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compartilhar “\(display.boardName)”")
                .font(.headline)
                .lineLimit(2)
            statusLine
            Divider()
            access
            if let live {
                Divider()
                liveSection(live)
            }
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

    // MARK: Live Share

    /// O Live Share do mural: o botão para começar, o progresso de quem está entrando, ou quem está ao vivo e o botão para sair.
    private func liveSection(_ live: LiveShareDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch live.state {
            case .unavailable(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ready(let inCall):
                Button(action: onStartLive) {
                    Label("Live Share…", systemImage: "shareplay")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("share-live-button")
                Text(inCall ? "Começa na chamada do FaceTime em andamento." : "Escolha com quem fazer uma chamada do FaceTime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Entrando no Live Share…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            case .live(let people, let unverifiedCount):
                liveNow(people: people, unverifiedCount: unverifiedCount)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share-live-section")
    }

    /// Quem está ao vivo (bolinha na cor, nome e o que faz), o aviso de quem está sem acesso e o botão para sair.
    private func liveNow(people: [LiveShareDisplay.Person], unverifiedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ao vivo agora", systemImage: "shareplay")
                .font(.callout.weight(.semibold))
            if people.isEmpty {
                Text("Esperando as outras pessoas…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(people) { person in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(LivePalette.color(person.colorIndex))
                                .frame(width: 9, height: 9)
                                .padding(.top, 4)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name)
                                Text(person.activity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("share-live-person")
                    }
                }
                .font(.callout)
            }
            if unverifiedCount > 0 {
                Text(
                    unverifiedCount == 1
                        ? "1 pessoa na chamada não tem acesso a este mural."
                        : "\(unverifiedCount) pessoas na chamada não têm acesso a este mural."
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("share-live-no-access")
            }
            Button(action: onLeaveLive) {
                Text("Sair do Live Share")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("share-live-leave-button")
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if showsInvite, let shareItem {
                ShareLink(item: shareItem, preview: SharePreview(display.boardName)) {
                    Text(shareItem.share == nil ? "Convidar pessoas…" : "Gerenciar pessoas…")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("share-invite-button")
            }
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

#Preview("Popover com Live Share", traits: .fixedLayout(width: 1040, height: 520)) {
    LiveSharePopoverGallery()
}

#Preview("Popover com Live Share (escuro)", traits: .fixedLayout(width: 1040, height: 520)) {
    LiveSharePopoverGallery()
        .preferredColorScheme(.dark)
}

/// Os murais de exemplo das galerias.
private enum SharePopoverSamples {
    static let zone = CloudZoneID(name: "mural-de-exemplo")

    static let ownerShared = ShareDisplay(
        boardName: "Viagem a Lisboa",
        cloud: BoardCloudInfo(
            database: .private, zoneName: zone.name, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner),
        share: ShareSummary(
            zone: zone, currentUserPermission: .owner,
            participants: [
                .init(displayName: "Bia Souza", userRecordName: "bia", permission: .readWrite, isAccepted: true),
                .init(displayName: "Caio", userRecordName: "caio", permission: .readOnly, isAccepted: true),
                .init(displayName: nil, userRecordName: "pendente", permission: .readWrite, isAccepted: false),
            ]),
        issue: nil, isSending: false, accountAvailable: true)

    static let guestReadOnly = ShareDisplay(
        boardName: "Receitas da família",
        cloud: BoardCloudInfo(
            database: .shared, zoneName: zone.name, zoneOwnerName: "dono", ownerDisplayName: "Ana Lima", permission: .readOnly),
        share: nil, issue: .readOnly, isSending: false, accountAvailable: true)

    static let guestEditing = ShareDisplay(
        boardName: "Receitas da família",
        cloud: BoardCloudInfo(
            database: .shared, zoneName: zone.name, zoneOwnerName: "dono", ownerDisplayName: "Ana Lima", permission: .readWrite),
        share: nil, issue: nil, isSending: false, accountAvailable: true)

    static let withoutAccount = ShareDisplay(
        boardName: "Ideias soltas", cloud: nil, share: nil, issue: nil, isSending: false, accountAvailable: false)
}

/// O popover como o dono (mural compartilhado), o convidado que só vê e quem está sem conta do iCloud, lado a lado.
private struct SharePopoverGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(
                [SharePopoverSamples.ownerShared, SharePopoverSamples.guestReadOnly, SharePopoverSamples.withoutAccount],
                id: \.boardName
            ) { display in
                SharePopover(display: display)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

/// A seção do Live Share nos estados que o popover mostra: o dono pronto para começar, o dono ao vivo (com duas pessoas e uma sem
/// acesso) e o convidado entrando.
private struct LiveSharePopoverGallery: View {
    private static let people: [LiveShareDisplay.Person] = [
        .init(
            id: UUID(uuidString: "00000001-0000-4000-8000-000000000000")!, name: "Bia Souza", colorIndex: 1,
            activity: "editando “Roteiro de sábado”"),
        .init(id: UUID(uuidString: "00000002-0000-4000-8000-000000000000")!, name: "Caio", colorIndex: 4, activity: "no mural"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            popover(SharePopoverSamples.ownerShared, live: .ready(inCall: false))
            popover(SharePopoverSamples.ownerShared, live: .live(people: Self.people, unverifiedCount: 1))
            popover(SharePopoverSamples.guestEditing, live: .connecting)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private func popover(_ display: ShareDisplay, live state: LiveShareDisplay.State) -> some View {
        SharePopover(display: display, live: LiveShareDisplay(state: state))
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}
