import CoreGraphics
import Foundation
import MuralKit
import MuralSync

/// Quem pode estar no Live Share de um mural: o dono e os convidados que aceitaram o convite, e a própria pessoa deste Mac (que pode
/// estar em outro Mac). Quem diz ser alguém no Live Share é conferido contra esta lista.
nonisolated struct LiveRoster: Equatable, Sendable {
    /// Os `userRecordName` que entram.
    private var members: Set<String> = []
    /// O nome que o convite dá a cada um, quando dá.
    private var names: [String: String] = [:]

    /// - Parameters:
    ///   - share: o convite do mural; `nil` quando o mural não tem convite.
    ///   - localUserRecordName: o `userRecordName` da pessoa deste Mac. Entra sem nome: pode ser ela em outro Mac.
    init(share: ShareSummary?, localUserRecordName: String?) {
        if let share {
            add(share.ownerUserRecordName, name: share.ownerDisplayName)
            for participant in share.participants where participant.isAccepted {
                add(participant.userRecordName, name: participant.displayName)
            }
        }
        add(localUserRecordName, name: nil)
    }

    /// A pessoa está no convite do mural, ou é a deste Mac. Sem `userRecordName` ninguém entra.
    func allows(_ userRecordName: String?) -> Bool {
        guard let userRecordName else { return false }
        return members.contains(userRecordName)
    }

    /// O nome que o convite dá à pessoa; `nil` quando não dá (a própria pessoa, ou quem o iCloud não nomeou).
    func name(of userRecordName: String) -> String? {
        names[userRecordName]
    }

    private mutating func add(_ userRecordName: String?, name: String?) {
        // No Mac do dono o CloudKit põe este marcador no lugar do nome real: ele não identifica ninguém.
        guard let userRecordName, !userRecordName.isEmpty, userRecordName != CloudZoneID.defaultOwnerName else { return }
        members.insert(userRecordName)
        if let name, !name.isEmpty, names[userRecordName] == nil { names[userRecordName] = name }
    }
}

/// Uma pessoa no Live Share do mural, como a interface a vê.
nonisolated struct LivePeer: Identifiable, Equatable, Sendable {
    /// O `Participant.id` do SharePlay.
    let id: UUID
    var name: String
    /// O que a pessoa disse ser no `hello`.
    var userRecordName: String?
    /// O convite do mural confere com o que a pessoa disse. Só quem é conferido aparece e é ouvido.
    var isVerified: Bool
    /// O lugar da pessoa na paleta, igual em todos os Macs (`LivePresence.colorIndex(for:)`).
    var colorIndex: Int
    /// Onde está o ponteiro, em pontos do mural; `nil` quando não está sobre o mural.
    var pointer: CGPoint?
    var drag: LiveDrag?
    var focus: LiveFocus?
}

/// O que o controlador faz depois de uma mensagem.
nonisolated struct LiveReaction: Equatable, Sendable {
    /// Responder com o `hello` daqui só a esta pessoa.
    var replyHelloTo: UUID?
    /// Uma pessoa conferida enviou mudanças ao iCloud: buscar já.
    var fetchRequested = false
    /// Chegou um `hello` que o convite conhecido não confere: reler o convite.
    var needsRosterRefresh = false
}

/// A presença no Live Share de um mural, função pura das mensagens: o controlador guarda, a interface lê.
nonisolated struct LivePresence: Equatable, Sendable {
    static let paletteCount = 8

    let boardID: BoardID
    private(set) var roster: LiveRoster
    private(set) var peers: [UUID: LivePeer] = [:]
    /// A última lista de participantes da sessão: só sai de `peers` quem estava nela e não está mais.
    private var participants: Set<UUID> = []
    /// O nome que cada pessoa disse ter no `hello`, para refazer o nome quando o convite mudar.
    private var announcedNames: [UUID: String] = [:]
    /// Quem já fez o convite ser relido por um `hello` não conferido: cada pessoa faz isso uma vez.
    private var rosterRefreshAsked: Set<UUID> = []

    init(boardID: BoardID, roster: LiveRoster) {
        self.boardID = boardID
        self.roster = roster
    }

    /// A cor da pessoa, igual em todos os Macs.
    static func colorIndex(for id: UUID) -> Int {
        Int(id.uuid.0) % paletteCount
    }

    var verifiedIDs: Set<UUID> {
        Set(peers.values.filter(\.isVerified).map(\.id))
    }

    /// As pessoas conferidas, pelo nome (e pelo id no empate).
    var visiblePeers: [LivePeer] {
        peers.values.filter(\.isVerified).sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// Quantas pessoas disseram quem são e não estão no convite.
    var unverifiedCount: Int {
        peers.values.filter { !$0.isVerified }.count
    }

    /// A sessão disse quem está nela agora, sem esta pessoa. Quem estava na lista anterior e não está mais sai; quem só mandou
    /// mensagem e ainda não apareceu em nenhuma lista fica, porque a lista pode chegar depois da mensagem.
    /// - Returns: quem chegou, para receber o `hello` daqui.
    @discardableResult
    mutating func setParticipants(_ ids: Set<UUID>) -> Set<UUID> {
        let previous = participants
        participants = ids
        for gone in previous.subtracting(ids) { forget(gone) }
        return ids.subtracting(previous)
    }

    /// O convite mudou: refaz a conferência e o nome de quem já disse `hello`. Quem perde a conferência perde ponteiro, arrasto e foco.
    mutating func setRoster(_ roster: LiveRoster) {
        self.roster = roster
        let announcedNames = announcedNames
        peers = peers.mapValues { peer in
            var peer = peer
            let wasVerified = peer.isVerified
            peer.isVerified = roster.allows(peer.userRecordName)
            peer.name = Self.name(of: peer.userRecordName, in: roster, announced: announcedNames[peer.id])
            if wasVerified && !peer.isVerified {
                peer.pointer = nil
                peer.drag = nil
                peer.focus = nil
            }
            return peer
        }
    }

    /// Uma mensagem do canal confiável. Mensagem de outro mural não muda nada, e só `hello` e `bye` valem de quem não foi conferido.
    @discardableResult
    mutating func receive(_ event: LiveEvent, from peerID: UUID) -> LiveReaction {
        switch event {
        case .hello(let hello):
            guard hello.boardID == boardID else { return LiveReaction() }
            return apply(hello, from: peerID)
        case .saved(let id):
            guard id == boardID, peers[peerID]?.isVerified == true else { return LiveReaction() }
            return LiveReaction(fetchRequested: true)
        case .focus(let id, let focus):
            if id == boardID { updateVerified(peerID) { $0.focus = focus } }
        case .dragEnded(let id):
            if id == boardID { updateVerified(peerID) { $0.drag = nil } }
        case .pointerLeft(let id):
            if id == boardID { updateVerified(peerID) { $0.pointer = nil } }
        case .bye:
            forget(peerID)
        }
        return LiveReaction()
    }

    /// Uma mensagem do canal sem garantia, só de pessoa conferida. Quem manda o ponteiro não está arrastando: o ponteiro limpa o
    /// arrasto, o que desfaz um arrasto preso quando um movimento atrasado chega depois do `dragEnded`. O arrasto não mexe no ponteiro.
    mutating func receive(_ motion: LiveMotion, from peerID: UUID) {
        switch motion {
        case .pointer(let id, let x, let y):
            guard id == boardID else { return }
            updateVerified(peerID) {
                $0.pointer = CGPoint(x: x, y: y)
                $0.drag = nil
            }
        case .drag(let id, let drag):
            guard id == boardID else { return }
            updateVerified(peerID) { $0.drag = drag }
        }
    }

    // MARK: Privado

    private mutating func apply(_ hello: LiveHello, from peerID: UUID) -> LiveReaction {
        var reaction = LiveReaction()
        let announced = hello.displayName.flatMap { $0.isEmpty ? nil : $0 }
        announcedNames[peerID] = announced

        var peer = peers[peerID] ?? LivePeer(id: peerID, name: "", isVerified: false, colorIndex: Self.colorIndex(for: peerID))
        peer.userRecordName = hello.userRecordName
        peer.name = Self.name(of: hello.userRecordName, in: roster, announced: announced)
        peer.isVerified = roster.allows(hello.userRecordName)
        peer.focus = hello.focus
        if !peer.isVerified {
            peer.pointer = nil
            peer.drag = nil
            if rosterRefreshAsked.insert(peerID).inserted { reaction.needsRosterRefresh = true }
        }
        peers[peerID] = peer

        // A resposta só diz quem é esta pessoa, e o convite do outro lado pode estar desatualizado: vai também a quem não foi conferido.
        if hello.replyRequested { reaction.replyHelloTo = peerID }
        return reaction
    }

    /// O nome da pessoa: o do convite, senão o que o Mac dela disse, senão "Convidado".
    private static func name(of userRecordName: String?, in roster: LiveRoster, announced: String?) -> String {
        if let userRecordName, let name = roster.name(of: userRecordName) { return name }
        return announced ?? "Convidado"
    }

    private mutating func updateVerified(_ peerID: UUID, _ change: (inout LivePeer) -> Void) {
        guard var peer = peers[peerID], peer.isVerified else { return }
        change(&peer)
        peers[peerID] = peer
    }

    private mutating func forget(_ peerID: UUID) {
        peers[peerID] = nil
        announcedNames[peerID] = nil
        rosterRefreshAsked.remove(peerID)
    }
}
