import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Um lançador de mentira: registra as aberturas, pode falhar, demorar e simular a edição da pessoa.
@MainActor
final class FakeEditorLauncher: PasteEditorLaunching {
    struct Failure: LocalizedError {
        var errorDescription: String? { "sem permissão" }
    }

    private(set) var calls: [(file: URL, application: URL)] = []
    var failure: (any Error)?
    var delay: Duration?
    /// Se definido, o arquivo de texto passa a ter este conteúdo depois de aberto (a pessoa digitou e salvou).
    var editedText: String?

    func open(_ file: URL, with application: URL) async throws {
        calls.append((file, application))
        if let delay { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        if let editedText { try Data(editedText.utf8).write(to: file) }
    }
}

@MainActor
private final class Clock {
    var date = Date()
}

@MainActor
struct PasteEditorTests {
    private let app = PasteEditorApp(
        name: "Editor Teste", bundleIdentifier: "com.exemplo.Teste", url: URL(filePath: "/Applications/Teste.app"))

    private func makeRoots() throws -> (roots: PasteEditFiles.Roots, base: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PasteEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return (
            PasteEditFiles.Roots(
                inside: base.appendingPathComponent("inside", isDirectory: true),
                visible: base.appendingPathComponent("visible", isDirectory: true)), base
        )
    }

    private func makeEditor(
        roots: PasteEditFiles.Roots, launcher: FakeEditorLauncher, clock: Clock? = nil
    ) -> PasteEditor {
        let app = app
        return PasteEditor(
            roots: roots, launcher: launcher, resolve: { _ in app }, now: { clock?.date ?? Date() })
    }

    private func board(_ name: String = "Casa") -> BoardLibraryEntry {
        let id = BoardID()
        return BoardLibraryEntry(manifest: BoardManifest(id: id, name: name), route: .saved(id))
    }

    private func pngContent() -> PasteboardImporter.Content {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return .data(rep.representation(using: .png, properties: [:])!, fileExtension: "png", kind: .image, title: "x")
    }

    private func entries(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func opened(_ outcome: PasteEditor.BeginOutcome) throws -> PasteEditor.Pending {
        guard case .opened(let pending) = outcome else {
            Issue.record("deveria abrir: \(outcome)")
            throw CancellationError()
        }
        return pending
    }

    // MARK: Começar

    @Test("Texto: grava na raiz de dentro, abre no app e fica pendente")
    func beginText() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        let editor = makeEditor(roots: roots, launcher: launcher)
        var changes: [Bool] = []
        editor.onPendingChange = { changes.append($0) }
        let casa = board()

        let pending = try opened(await editor.begin(.text("Olá"), as: .text, board: casa))

        #expect(editor.pending == pending)
        #expect(pending.boardID == casa.manifest.id)
        #expect(pending.boardName == "Casa")
        #expect(pending.editor == app)
        #expect(pending.session.file.path.hasPrefix(roots.inside.path + "/"))
        #expect(launcher.calls.count == 1)
        #expect(launcher.calls.first?.file == pending.session.file)
        #expect(launcher.calls.first?.application == app.url)
        #expect(changes == [true])
    }

    @Test("Imagem: grava na raiz visível")
    func beginImage() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let editor = makeEditor(roots: roots, launcher: FakeEditorLauncher())

        let pending = try opened(await editor.begin(pngContent(), as: .image, board: board()))

        #expect(pending.session.file.path.hasPrefix(roots.visible.path + "/"))
        #expect(pending.session.file.pathExtension == "png")
    }

    @Test("Sem app que abra o tipo, a edição não começa e nada é gravado")
    func beginWithoutAnEditor() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let editor = PasteEditor(roots: roots, launcher: FakeEditorLauncher(), resolve: { _ in nil })

        let outcome = await editor.begin(.text("Olá"), as: .text, board: board())

        #expect(outcome == .failed("Nenhum app deste Mac abre esse tipo de conteúdo."))
        #expect(editor.pending == nil)
        #expect(entries(of: roots.inside).isEmpty)
    }

    @Test("Falha ao abrir: avisa com o nome do app, apaga a cópia e guarda o erro uma vez")
    func launcherFailure() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        launcher.failure = FakeEditorLauncher.Failure()
        let editor = makeEditor(roots: roots, launcher: launcher)
        var changes: [Bool] = []
        editor.onPendingChange = { changes.append($0) }

        let outcome = await editor.begin(.text("Olá"), as: .text, board: board())

        guard case .failed(let message) = outcome else {
            Issue.record("deveria falhar")
            return
        }
        #expect(message.contains("Editor Teste"))
        #expect(message.contains("sem permissão"))
        #expect(editor.pending == nil)
        #expect(changes.isEmpty)
        #expect(entries(of: roots.inside).isEmpty)
        #expect(editor.takeLastFailure() == message)
        #expect(editor.takeLastFailure() == nil)
    }

    @Test("Com uma edição pendente, outra é recusada e nenhuma pasta nova aparece")
    func secondBeginWhilePending() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let editor = makeEditor(roots: roots, launcher: FakeEditorLauncher())
        _ = try opened(await editor.begin(.text("Olá"), as: .text, board: board()))
        let before = entries(of: roots.inside)

        let outcome = await editor.begin(.text("Outro"), as: .text, board: board())

        #expect(
            outcome == .failed("Já há uma edição esperando para ser colada. Cole ou descarte antes de editar outra coisa."))
        #expect(entries(of: roots.inside) == before)
        // A recusa volta só para quem pediu: não fica guardada para a próxima abertura do painel.
        #expect(editor.takeLastFailure() == nil)
    }

    @Test("Enquanto o editor ainda está abrindo, outra edição é recusada")
    func beginWhileAnotherIsInFlight() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        launcher.delay = .milliseconds(400)
        let editor = makeEditor(roots: roots, launcher: launcher)
        let first = Task { await editor.begin(.text("Olá"), as: .text, board: board()) }
        for _ in 0..<100 where launcher.calls.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(launcher.calls.count == 1)

        let second = await editor.begin(.text("Outro"), as: .text, board: board())

        #expect(second == .failed("O editor ainda está abrindo."))
        _ = try opened(await first.value)
        #expect(entries(of: roots.inside).count == 1)
    }

    @Test("Cancelar quem chamou não interrompe: a edição fica pendente do mesmo jeito")
    func cancelledCallerStillEndsPending() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        launcher.delay = .milliseconds(100)
        let editor = makeEditor(roots: roots, launcher: launcher)

        let task = Task { await editor.begin(.text("Olá"), as: .text, board: board()) }
        task.cancel()
        let pending = try opened(await task.value)

        #expect(editor.pending == pending)
        #expect(launcher.calls.count == 1)
    }

    // MARK: Ler, reabrir e encerrar

    @Test("Depois da edição, a leitura traz o texto editado")
    func readAfterAnEdit() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        launcher.editedText = "Olá mundo"
        let editor = makeEditor(roots: roots, launcher: launcher)
        _ = try opened(await editor.begin(.text("Olá"), as: .text, board: board()))

        guard case .text(let text) = try await editor.read() else {
            Issue.record("deveria ler texto")
            return
        }

        #expect(text == "Olá mundo")
    }

    @Test("Sem edição pendente, ler falha como cópia não encontrada")
    func readWithoutPending() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let editor = makeEditor(roots: roots, launcher: FakeEditorLauncher())

        await #expect(throws: PasteEditFiles.Failure.missing) { try await editor.read() }
    }

    @Test("Encerrar ou descartar uma imagem apaga a pasta e avisa; o texto deixa a cópia para a limpeza")
    func finishAndDiscard() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let editor = makeEditor(roots: roots, launcher: FakeEditorLauncher())
        var changes: [Bool] = []
        editor.onPendingChange = { changes.append($0) }

        let image = try opened(await editor.begin(pngContent(), as: .image, board: board()))
        await editor.finish()
        #expect(editor.pending == nil)
        #expect(!exists(image.session.folder))

        let discarded = try opened(await editor.begin(pngContent(), as: .image, board: board()))
        await editor.discard()
        #expect(!exists(discarded.session.folder))

        let text = try opened(await editor.begin(.text("Olá"), as: .text, board: board()))
        await editor.finish()
        #expect(editor.pending == nil)
        #expect(exists(text.session.folder))
        #expect(changes == [true, false, true, false, true, false])
    }

    @Test("Reabrir chama o editor de novo; sem o arquivo ou sem edição, devolve a frase do problema")
    func reopen() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let launcher = FakeEditorLauncher()
        let editor = makeEditor(roots: roots, launcher: launcher)
        #expect(await editor.reopen() == PasteEditFiles.Failure.missing.errorDescription)

        let pending = try opened(await editor.begin(.text("Olá"), as: .text, board: board()))
        #expect(await editor.reopen() == nil)
        #expect(launcher.calls.count == 2)
        #expect(launcher.calls.last?.file == pending.session.file)

        launcher.failure = FakeEditorLauncher.Failure()
        let failed = await editor.reopen()
        #expect(failed?.contains("Editor Teste") == true)

        launcher.failure = nil
        try FileManager.default.removeItem(at: pending.session.file)
        #expect(await editor.reopen() == PasteEditFiles.Failure.missing.errorDescription)
    }

    // MARK: Limpeza

    @Test("A limpeza poupa a edição pendente e apaga a cópia esquecida")
    func sweepKeepsThePending() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let clock = Clock()
        let editor = makeEditor(roots: roots, launcher: FakeEditorLauncher(), clock: clock)
        let pending = try opened(await editor.begin(.text("Olá"), as: .text, board: board()))
        let forgotten = roots.inside.appendingPathComponent(
            PasteEditFiles.folderName(id: UUID(), createdAt: clock.date.addingTimeInterval(-3 * PasteEditFiles.maxAge)),
            isDirectory: true)
        try FileManager.default.createDirectory(at: forgotten, withIntermediateDirectories: true)
        clock.date = clock.date.addingTimeInterval(2 * PasteEditFiles.maxAge)

        editor.sweep()

        #expect(exists(pending.session.folder))
        #expect(!exists(forgotten))
    }
}
