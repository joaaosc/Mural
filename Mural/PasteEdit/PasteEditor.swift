import Foundation
import MuralKit
import Observation

/// A edição em andamento de um conteúdo copiado: grava a cópia, abre no app de edição, guarda o que ficou esperando para
/// ser colado e lê o resultado de volta.
///
/// Há uma edição por vez. O objeto vive durante toda a sessão do app, junto de `BoardDelivery`: o painel da barra de menus
/// monta um modelo novo a cada abertura e se fecha quando o editor ganha o foco, então a edição não pode morar nele. Quem
/// abre o painel de novo encontra aqui a edição pendente (``pending``) e o último erro (``takeLastFailure()``).
@MainActor
@Observable
final class PasteEditor {
    /// Uma edição aberta no app de edição, à espera de ser colada.
    struct Pending: Equatable, Sendable {
        let session: PasteEditFiles.Session
        let editor: PasteEditorApp
        /// O mural escolhido para receber o conteúdo editado.
        let boardID: BoardID
        let boardName: String
    }

    /// O resultado de ``begin(_:as:board:)``.
    enum BeginOutcome: Equatable, Sendable {
        case opened(Pending)
        /// A frase, pronta para mostrar, de por que a edição não começou.
        case failed(String)
    }

    /// A edição aberta; `nil` sem nenhuma.
    private(set) var pending: Pending?

    /// Avisado, na hora, de que passou a existir (`true`) ou deixou de existir (`false`) uma edição pendente.
    @ObservationIgnored var onPendingChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let roots: PasteEditFiles.Roots
    @ObservationIgnored private let launcher: any PasteEditorLaunching
    @ObservationIgnored private let resolve: @MainActor (PasteEditKind) -> PasteEditorApp?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var isBeginning = false
    @ObservationIgnored private var lastFailure: String?

    init(
        roots: PasteEditFiles.Roots, launcher: any PasteEditorLaunching,
        resolve: @escaping @MainActor (PasteEditKind) -> PasteEditorApp? = { PasteEditorResolver.editor(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.roots = roots
        self.launcher = launcher
        self.resolve = resolve
        self.now = now
    }

    /// O app que edita o tipo, para o título das linhas ("Editar no TextEdit"); `nil` esconde a opção de editar.
    func editor(for kind: PasteEditKind) -> PasteEditorApp? {
        resolve(kind)
    }

    /// Grava o conteúdo, abre no app de edição e passa a esperar pela edição.
    ///
    /// O trabalho roda numa tarefa do próprio editor: cancelar quem chama (a tarefa de colar do painel é cancelada quando o
    /// painel some, justamente porque o editor tomou o foco) não interrompe a gravação nem a abertura, e a edição fica
    /// pendente do mesmo jeito. As falhas de gravar ou de abrir também ficam guardadas para ``takeLastFailure()``, porque
    /// podem chegar com o painel já fechado; as recusas imediatas (outra edição pendente ou abrindo, nenhum app) só voltam
    /// no resultado, para quem acabou de pedir.
    func begin(_ content: PasteboardImporter.Content, as kind: PasteEditKind, board: BoardLibraryEntry) async -> BeginOutcome {
        if isBeginning { return .failed("O editor ainda está abrindo.") }
        if pending != nil {
            return .failed("Já há uma edição esperando para ser colada. Cole ou descarte antes de editar outra coisa.")
        }
        guard let editor = resolve(kind) else { return .failed("Nenhum app deste Mac abre esse tipo de conteúdo.") }

        isBeginning = true
        let roots = roots
        let launcher = launcher
        let date = now()
        let boardName = board.manifest.name
        let task = Task { () -> Result<PasteEditFiles.Session, PasteEditFailure> in
            await Self.sweepOffMain(roots: roots, now: date)
            let session: PasteEditFiles.Session
            do {
                session = try await PasteEditFiles.write(content, as: kind, boardName: boardName, roots: roots, now: date)
            } catch {
                return .failure(PasteEditFailure(message: error.localizedDescription))
            }
            do {
                try await launcher.open(session.file, with: editor.url)
            } catch {
                await PasteEditFiles.remove(session)
                return .failure(
                    PasteEditFailure(message: "Não foi possível abrir com \(editor.name): \(error.localizedDescription)"))
            }
            return .success(session)
        }
        let result = await task.value
        isBeginning = false

        switch result {
        case .failure(let failure):
            return fail(failure.message)
        case .success(let session):
            let opened = Pending(session: session, editor: editor, boardID: board.manifest.id, boardName: boardName)
            pending = opened
            onPendingChange?(true)
            return .opened(opened)
        }
    }

    /// O último erro de uma edição, uma vez só: depois de entregue, volta a `nil`.
    func takeLastFailure() -> String? {
        defer { lastFailure = nil }
        return lastFailure
    }

    /// Abre de novo a edição pendente no mesmo app, para quem fechou a janela do editor sem colar.
    /// - Returns: `nil` quando abriu; senão a frase do que impediu (arquivo que sumiu ou app que não abriu).
    func reopen() async -> String? {
        guard let pending else { return PasteEditFiles.Failure.missing.errorDescription }
        let file: URL
        do {
            file = try PasteEditFiles.locate(pending.session)
        } catch {
            return error.localizedDescription
        }
        do {
            try await launcher.open(file, with: pending.editor.url)
            return nil
        } catch {
            return "Não foi possível abrir com \(pending.editor.name): \(error.localizedDescription)"
        }
    }

    /// Lê a edição de volta, de forma coordenada (o editor grava o que ainda não salvou antes).
    /// - Throws: ``PasteEditFiles/Failure/missing`` sem edição pendente; os demais erros de ``PasteEditFiles/read(_:timeout:)``.
    func read() async throws -> PasteboardImporter.Content {
        guard let pending else { throw PasteEditFiles.Failure.missing }
        return try await PasteEditFiles.read(pending.session)
    }

    /// Encerra a edição depois de o conteúdo ter sido colado.
    func finish() async {
        await clear()
    }

    /// Descarta a edição pendente, sem colar.
    func discard() async {
        await clear()
    }

    /// Apaga as cópias esquecidas há mais de um dia, poupando a edição pendente. Chamada na abertura do app.
    func sweep() {
        let keeping = pending.map { [$0.session.folder] } ?? []
        PasteEditFiles.sweep(roots: roots, keeping: Set(keeping), now: now())
    }

    // MARK: Interno

    /// Imagem e PDF ficam na pasta visível (Downloads): apagar de imediato fecha a janela da Pré-Visualização e não deixa
    /// arquivo solto onde a pessoa o veria. O texto fica no contêiner do app e o Texto mantém a janela aberta, sem avisar, mesmo
    /// com o arquivo apagado; por isso a cópia de texto espera pela limpeza de 24 horas, em vez de sumir debaixo do editor.
    private func clear() async {
        guard let current = pending else { return }
        pending = nil
        onPendingChange?(false)
        if current.session.kind != .text {
            await PasteEditFiles.remove(current.session)
        }
    }

    private func fail(_ message: String) -> BeginOutcome {
        lastFailure = message
        return .failed(message)
    }

    @concurrent
    private static func sweepOffMain(roots: PasteEditFiles.Roots, now: Date) async {
        PasteEditFiles.sweep(roots: roots, now: now)
    }
}

/// O motivo de a edição não ter começado, como a frase que a pessoa lê.
private struct PasteEditFailure: Error, Sendable {
    let message: String
}
