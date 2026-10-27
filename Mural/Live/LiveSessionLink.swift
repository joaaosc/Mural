import Combine
import Foundation
import GroupActivities
import os

/// Para quem vai uma mensagem: todas as pessoas da sessão, ou só algumas (pelo `Participant.id`).
nonisolated enum LiveRecipients: Equatable, Sendable {
    case all
    case only(Set<UUID>)
}

/// O estado de uma sessão do Live Share como o controlador o usa.
nonisolated enum LiveSessionState: Equatable, Sendable {
    case waiting
    case joined
    case invalidated
}

/// O que a sessão avisa ao controlador, sempre no Main Actor.
struct LiveSessionHandlers {
    var stateChanged: @MainActor (LiveSessionState) -> Void
    /// Quem está na sessão agora, sem a pessoa deste Mac.
    var participantsChanged: @MainActor (Set<UUID>) -> Void
    var event: @MainActor (LiveEvent, UUID) -> Void
    var motion: @MainActor (LiveMotion, UUID) -> Void
}

/// Uma sessão do SharePlay vista pelo controlador do Live Share. A de verdade (`GroupSessionLink`) embrulha `GroupSession`; os
/// testes e a demonstração usam outras.
@MainActor
protocol LiveSessionLink: AnyObject {
    var activity: MuralLiveActivity { get }
    var state: LiveSessionState { get }
    /// Liga os avisos; chamado uma vez, antes de `join()`.
    func connect(_ handlers: LiveSessionHandlers)
    func join()
    func leave()
    func send(_ event: LiveEvent, to recipients: LiveRecipients)
    func send(_ motion: LiveMotion, to recipients: LiveRecipients)
}

/// A sessão do SharePlay de verdade: embrulha `GroupSession`, que não é `Sendable` e por isso fica no Main Actor. Guarda dois
/// mensageiros (o modo de entrega é fixo em cada um): o confiável, para `LiveEvent`, e o sem garantia, para `LiveMotion`.
///
/// Não tem teste automático: uma sessão só existe numa chamada do FaceTime. O que depende dela é testado no controlador, com uma
/// sessão falsa (`LiveSessionLink`).
@MainActor
final class GroupSessionLink: LiveSessionLink {
    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "Live Share")

    let activity: MuralLiveActivity
    private let session: GroupSession<MuralLiveActivity>
    private let reliable: GroupSessionMessenger
    private let unreliable: GroupSessionMessenger
    /// Quem está na sessão agora, sem a pessoa deste Mac, pelo `Participant.id`.
    private var participants: [UUID: Participant] = [:]
    private var handlers: LiveSessionHandlers?
    /// O último estado avisado ao controlador: o mesmo estado não é avisado duas vezes.
    private var reportedState: LiveSessionState?
    private var subscriptions: Set<AnyCancellable> = []
    private var tasks: [Task<Void, Never>] = []
    /// O fim da fila de envios do canal confiável: cada mensagem espera a anterior, para chegarem na ordem em que saíram daqui e para
    /// a despedida (`bye`) sair antes de a pessoa deixar a sessão.
    private var reliableSends: Task<Void, Never>?

    init(session: GroupSession<MuralLiveActivity>) {
        self.session = session
        activity = session.activity
        reliable = GroupSessionMessenger(session: session)
        unreliable = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
    }

    var state: LiveSessionState { Self.state(of: session.state) }

    /// Liga os avisos do estado e dos participantes (do Combine, trazidos de volta à fila principal) e as duas tarefas que recebem as
    /// mensagens. Quem chama liga isto antes de `join()`.
    func connect(_ handlers: LiveSessionHandlers) {
        guard self.handlers == nil else { return }
        self.handlers = handlers

        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.sessionStateChanged(Self.state(of: state)) }
            .store(in: &subscriptions)
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.activeParticipantsChanged(active) }
            .store(in: &subscriptions)

        let reliable = reliable
        tasks.append(
            Task { [weak self] in
                for await (event, context) in reliable.messages(of: LiveEvent.self) {
                    self?.handlers?.event(event, context.source.id)
                }
            })
        let unreliable = unreliable
        tasks.append(
            Task { [weak self] in
                for await (motion, context) in unreliable.messages(of: LiveMotion.self) {
                    self?.handlers?.motion(motion, context.source.id)
                }
            })
    }

    func join() {
        session.join()
    }

    /// Deixa a sessão depois de as mensagens confiáveis em fila saírem. Não faz nada se ela já terminou, agora ou quando a fila
    /// esvaziar: `leave()` numa sessão encerrada não é permitido.
    func leave() {
        guard state != .invalidated else { return }
        let pending = reliableSends
        let session = session
        Task {
            await pending?.value
            if case .invalidated = session.state { return }
            session.leave()
        }
    }

    func send(_ event: LiveEvent, to recipients: LiveRecipients) {
        guard let destination = destination(for: recipients) else { return }
        let messenger = reliable
        let previous = reliableSends
        reliableSends = Task {
            await previous?.value
            await Self.deliver(event, to: destination, using: messenger)
        }
    }

    func send(_ motion: LiveMotion, to recipients: LiveRecipients) {
        guard let destination = destination(for: recipients) else { return }
        let messenger = unreliable
        Task { await Self.deliver(motion, to: destination, using: messenger) }
    }

    // MARK: Privado

    private func sessionStateChanged(_ state: LiveSessionState) {
        guard state != reportedState else { return }
        reportedState = state
        handlers?.stateChanged(state)
        if state == .invalidated { stop() }
    }

    private func activeParticipantsChanged(_ active: Set<Participant>) {
        let local = session.localParticipant.id
        participants = Dictionary(active.filter { $0.id != local }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        handlers?.participantsChanged(Set(participants.keys))
    }

    /// A sessão terminou: nada mais chega nem sai.
    private func stop() {
        for task in tasks { task.cancel() }
        tasks = []
        subscriptions = []
    }

    /// Quem recebe, no formato do SharePlay. Os ids que não são de ninguém na sessão agora ficam de fora; sem ninguém, não se envia.
    private func destination(for recipients: LiveRecipients) -> Participants? {
        switch recipients {
        case .all:
            return .all
        case .only(let ids):
            let known = ids.compactMap { participants[$0] }
            return known.isEmpty ? nil : .only(Set(known))
        }
    }

    /// O erro de um envio (excesso de mensagens, tamanho) vai ao registro do sistema, nunca a quem pediu o envio.
    private static func deliver<Message: Codable & Sendable>(
        _ value: Message, to destination: Participants, using messenger: GroupSessionMessenger
    ) async {
        do {
            try await messenger.send(value, to: destination)
        } catch {
            log.error("Mensagem do Live Share não enviada: \(String(describing: error), privacy: .public)")
        }
    }

    private static func state(of state: GroupSession<MuralLiveActivity>.State) -> LiveSessionState {
        switch state {
        case .waiting: .waiting
        case .joined: .joined
        case .invalidated: .invalidated
        @unknown default: .invalidated
        }
    }
}
