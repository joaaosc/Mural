#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import MuralKit

/// O início do Live Share sem chamada do FaceTime, só para conferir a interface na janela de verdade (`-uiTesting -liveShareDemo`).
/// Em vez de pedir ao sistema, entrega ao controlador uma sessão de mentira (`LiveShareDemoLink`) com a Bia e o Caio.
///
/// Fluxo de conferência: criar um mural, "Convidar convidado de teste" no popover de Compartilhar e, depois, o botão do Live Share.
@MainActor
final class LiveShareDemoStarter: LiveActivityStarter {
    /// O controlador que recebe a sessão. Fraco: é ele quem guarda este início.
    weak var controller: LiveShareController?
    private let tabs: MuralTabs

    init(tabs: MuralTabs) {
        self.tabs = tabs
    }

    /// Sempre em chamada: o Live Share começa direto, sem a folha do sistema.
    var isInCall: Bool { true }

    /// Entrega a sessão ao controlador. O primeiro cartão solto do mural da aba é o que o Caio edita e arrasta; sem a aba carregada
    /// ou sem cartão solto, só o ponteiro da Bia se mexe.
    func start(_ activity: MuralLiveActivity, in window: NSWindow?) async throws -> LiveStartOutcome {
        let card = tabs.tab(for: activity.boardID)?.session.model?.rootItems.first
        await controller?.accept(LiveShareDemoLink(activity: activity, card: card))
        return .started
    }
}

/// A sessão de mentira da demonstração. Ao entrar, a Bia (o convidado de teste do convite) e o Caio (a própria pessoa, em outro Mac)
/// chegam e dizem quem são. Depois, a ~15 Hz, a Bia passeia o ponteiro em volta do centro do mural e, a cada 6 s, o Caio arrasta o
/// cartão por 2 s. Só as mensagens chegam: o mural de verdade não muda. O que o controlador envia não vai a lugar nenhum.
@MainActor
final class LiveShareDemoLink: LiveSessionLink {
    /// Os dois participantes. O primeiro byte escolhe a cor na paleta (`LivePresence.colorIndex`): 1 e 4, bem diferentes.
    static let bia = UUID(uuidString: "01000000-0000-4000-8000-0000000000B1")!
    static let caio = UUID(uuidString: "04000000-0000-4000-8000-0000000000CA")!

    private static let tick: Duration = .milliseconds(66)
    /// O ponteiro da Bia dá uma volta numa elipse a cada 4 s.
    private static let loopCenter = (x: 360.0, y: 260.0)
    private static let loopRadius = (x: 160.0, y: 120.0)
    private static let loopPeriod = 4.0
    /// O Caio arrasta o cartão por 2 s a cada 6 s, para a direita e para baixo.
    private static let dragPeriod = 6.0
    private static let dragDuration = 2.0
    private static let dragOffset = (x: 120.0, y: 60.0)

    let activity: MuralLiveActivity
    private(set) var state: LiveSessionState = .waiting
    /// O cartão que o Caio edita e arrasta; `nil` sem cartão solto.
    private let card: BoardItem?
    private var handlers: LiveSessionHandlers?
    private var task: Task<Void, Never>?
    /// O Caio está com o cartão na mão: o fim do arrasto ainda não foi avisado.
    private var isDragging = false

    init(activity: MuralLiveActivity, card: BoardItem?) {
        self.activity = activity
        self.card = card
    }

    // MARK: Roteiro

    /// Onde está o ponteiro da Bia, `seconds` depois de a sessão começar.
    static func biaPointer(at seconds: Double) -> CGPoint {
        let angle = 2 * Double.pi * seconds / loopPeriod
        return CGPoint(x: loopCenter.x + loopRadius.x * cos(angle), y: loopCenter.y + loopRadius.y * sin(angle))
    }

    /// Quanto do arrasto do Caio já andou (de 0 a 1), `seconds` depois de a sessão começar; `nil` fora do arrasto.
    static func caioDragProgress(at seconds: Double) -> Double? {
        let phase = seconds.truncatingRemainder(dividingBy: dragPeriod)
        return phase < dragDuration ? phase / dragDuration : nil
    }

    // MARK: LiveSessionLink

    func connect(_ handlers: LiveSessionHandlers) {
        self.handlers = handlers
    }

    /// Entra na sessão: a Bia e o Caio chegam, dizem quem são e o movimento começa.
    func join() {
        guard state == .waiting else { return }
        state = .joined
        handlers?.stateChanged(.joined)
        handlers?.participantsChanged([Self.bia, Self.caio])
        handlers?.event(hello(userRecordName: CloudSyncController.testGuest, name: "Bia", focus: nil), Self.bia)
        let editing = card.map { LiveFocus(itemID: $0.id, isEditing: true) }
        handlers?.event(hello(userRecordName: CloudSyncController.testUser, name: "Caio", focus: editing), Self.caio)
        task = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            // `self` só é segurado durante o passo, não na espera: a demonstração não prende a sessão.
            while !Task.isCancelled {
                guard self?.advance(to: clock.now - start) != nil else { return }
                try? await clock.sleep(for: Self.tick)
            }
        }
    }

    /// Para o movimento e avisa que a sessão acabou. Sair de novo não avisa de novo.
    func leave() {
        task?.cancel()
        task = nil
        guard state != .invalidated else { return }
        state = .invalidated
        handlers?.stateChanged(.invalidated)
    }

    func send(_ event: LiveEvent, to recipients: LiveRecipients) {}

    func send(_ motion: LiveMotion, to recipients: LiveRecipients) {}

    // MARK: Privado

    private func hello(userRecordName: String, name: String, focus: LiveFocus?) -> LiveEvent {
        .hello(
            LiveHello(
                boardID: activity.boardID, userRecordName: userRecordName, displayName: name, focus: focus, replyRequested: false))
    }

    /// Um passo do roteiro: o ponteiro da Bia e, havendo cartão, o arrasto do Caio (com o aviso de fim quando ele larga).
    private func advance(to elapsed: Duration) {
        let seconds = Self.seconds(elapsed)
        let board = activity.boardID
        let pointer = Self.biaPointer(at: seconds)
        handlers?.motion(.pointer(boardID: board, x: pointer.x, y: pointer.y), Self.bia)
        guard let card else { return }
        if let progress = Self.caioDragProgress(at: seconds) {
            isDragging = true
            let drag = LiveDrag(
                kind: .item, id: card.id, x: card.position.x + Self.dragOffset.x * progress,
                y: card.position.y + Self.dragOffset.y * progress)
            handlers?.motion(.drag(boardID: board, drag: drag), Self.caio)
        } else if isDragging {
            isDragging = false
            handlers?.event(.dragEnded(boardID: board), Self.caio)
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
#endif
