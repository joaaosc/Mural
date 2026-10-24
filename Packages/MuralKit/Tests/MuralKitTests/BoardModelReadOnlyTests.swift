import CoreGraphics
import Foundation
import ImageIO
import Observation
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@MainActor
@Suite("Mural só para ver")
struct BoardModelReadOnlyTests {
    static let message = "Este mural é só para ver: quem compartilhou não deu permissão para editar."
    static let noteBody = "- [ ] Pintar a porta\n- [x] Lixar o batente\n\nPrimeira frase. Segunda frase."

    // MARK: Cenário

    /// Um mural com um cartão de cada tipo que os métodos mexem, no disco e em memória, e os arquivos de origem para importar.
    private struct Scene {
        let model: BoardModel
        let store: BoardStore
        let root: URL
        let folder: BoardItem
        let inner: BoardItem
        let note: BoardItem
        let sticky: BoardItem
        let checklist: BoardItem
        let entry: ChecklistEntry
        let reminder: BoardItem
        let music: BoardItem
        let link: BoardItem
        let freeText: BoardFreeText
        let clip: BoardItem
        let clipSource: URL
        let imageSource: URL
        let png: Data
    }

    /// Uma ação com o valor de "nada feito" de cada método conferido dentro dela: `run(true)` num mural só para ver, `run(false)`
    /// num que se pode editar.
    private struct Action {
        let name: String
        /// `false` nas ações automáticas (lembretes, prévias, música), que recusam sem avisar.
        let warns: Bool
        let run: (_ readOnly: Bool) async -> Void

        init(_ name: String, warns: Bool = true, run: @escaping (_ readOnly: Bool) async -> Void) {
            self.name = name
            self.warns = warns
            self.run = run
        }
    }

    /// Em segundos inteiros, porque o `BoardStore` grava datas em ISO-8601 sem frações.
    private func stamp(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: 1_792_497_600 + Double(seconds))
    }

    private func pngData(width: Int = 6, height: Int = 4) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeScene(persistence: BoardModel.Persistence = .immediate) throws -> Scene {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralReadOnly-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Origem", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let clipSource = sources.appendingPathComponent("clipe.mov")
        try Data([7, 8, 9]).write(to: clipSource)
        let png = try pngData()
        let imageSource = sources.appendingPathComponent("figura.png")
        try png.write(to: imageSource)

        let folder = BoardItem(kind: .folder, title: "Pasta", createdAt: stamp(1), position: BoardPoint(x: 40, y: 40))
        let inner = BoardItem(
            kind: .sticky, title: "Dentro", createdAt: stamp(2), parentID: folder.id, text: "Dentro", stickyColor: .yellow)
        let note = BoardItem(kind: .text, title: "Tarefas", createdAt: stamp(3), position: BoardPoint(x: 400, y: 40), text: Self.noteBody)
        let sticky = BoardItem(
            kind: .sticky, title: "Tinta", createdAt: stamp(4), position: BoardPoint(x: 40, y: 400), text: "Tinta azul",
            stickyColor: .yellow)
        let entry = ChecklistEntry(text: "Leite")
        let checklist = BoardItem(
            kind: .checklist, title: "Compras", createdAt: stamp(5), position: BoardPoint(x: 400, y: 400),
            checklist: ChecklistDocument(title: "Compras", sections: [ChecklistSection(title: "Mercado", entries: [entry])]))
        let reminder = BoardItem(
            kind: .reminder, title: "Ligar", createdAt: stamp(6), position: BoardPoint(x: 760, y: 40),
            reminder: ReminderSnapshot(identifier: "R1", title: "Ligar"))
        let music = BoardItem(
            kind: .music, title: "Abbey Road", createdAt: stamp(7), position: BoardPoint(x: 760, y: 400),
            music: MusicSnapshot(kind: .album, catalogID: "1", title: "Abbey Road", subtitle: "The Beatles", trackCount: 17))
        let link = BoardItem(
            kind: .link, title: "apple.com", createdAt: stamp(8), position: BoardPoint(x: 40, y: 760),
            link: LinkInfo(url: URL(string: "https://www.apple.com/mac")!))
        let freeText = BoardFreeText(text: "Lembrar de ligar", position: BoardPoint(x: 400, y: 760), createdAt: stamp(9))

        let board = Board(items: [folder, inner, note, sticky, checklist, reminder, music, link], freeTexts: [freeText])
        let store = BoardStore(directory: root.appendingPathComponent("Mural", isDirectory: true))
        let model = BoardModel(board: board, store: store, persistence: persistence)
        let clip = try #require(model.importData(Data([1, 2, 3]), fileExtension: "mov", kind: .video, title: "Clipe"))
        return Scene(
            model: model, store: store, root: root, folder: folder, inner: inner, note: note, sticky: sticky, checklist: checklist,
            entry: entry, reminder: reminder, music: music, link: link, freeText: freeText, clip: clip, clipSource: clipSource,
            imageSource: imageSource, png: png)
    }

    private func makeReadOnlyScene() throws -> Scene {
        let scene = try makeScene()
        scene.model.isReadOnly = true
        return scene
    }

    private func cleanUp(_ scene: Scene) {
        try? FileManager.default.removeItem(at: scene.root)
    }

    /// Os nomes dos arquivos de `Items/`.
    private func storedFiles(_ scene: Scene) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: scene.store.itemsDirectory.path)) ?? []).sorted()
    }

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Todo método público que muda o mural, com o que ele deve devolver num mural só para ver e num que se pode editar.
    private func actions(for scene: Scene) -> [Action] {
        let model = scene.model
        let attachment = NoteAttachment(fileName: "\(UUID().uuidString).png", pixelWidth: 6, pixelHeight: 4)
        let changedReminder = ReminderSnapshot(identifier: "R1", title: "Ligar", isCompleted: true)
        return [
            // Entrada de conteúdo
            Action("importFiles") { readOnly in
                #expect(model.importFiles([scene.clipSource]).isEmpty == readOnly)
            },
            Action("importText") { readOnly in
                #expect((model.importText("Tinta azul") == nil) == readOnly)
            },
            Action("importText(as:)") { readOnly in
                #expect((model.importText("Tinta azul", as: .sticky) == nil) == readOnly)
            },
            Action("importData") { readOnly in
                #expect((model.importData(Data([1]), fileExtension: "mov", kind: .video, title: "Outro") == nil) == readOnly)
            },
            Action("importLinks") { readOnly in
                let draft = LinkDraft(url: URL(string: "https://www.swift.org")!)
                #expect(model.importLinks([draft]).isEmpty == readOnly)
            },
            Action("importMusic") { readOnly in
                #expect(model.importMusic([MusicSnapshot(kind: .album, catalogID: "9", title: "Revolver")]).isEmpty == readOnly)
            },
            Action("addReminders") { readOnly in
                #expect(model.addReminders([ReminderSnapshot(identifier: "R9", title: "Pagar")]).isEmpty == readOnly)
            },
            // Entrada de conteúdo fora do Main Actor
            Action("prepareFiles") { readOnly in
                #expect(await model.prepareFiles([scene.clipSource]).items.isEmpty == readOnly)
            },
            Action("prepareTypedFiles") { readOnly in
                let typed = BoardModel.TypedFile(url: scene.clipSource, contentTypeIdentifier: "com.apple.quicktime-movie")
                #expect(await model.prepareTypedFiles([typed]).items.isEmpty == readOnly)
            },
            Action("prepareData") { readOnly in
                let prepared = await model.prepareData(Data([1]), fileExtension: "mov", kind: .video, title: "Outro")
                #expect(prepared.items.isEmpty == readOnly)
            },
            Action("prepareNoteImage(data:)") { readOnly in
                #expect((await model.prepareNoteImage(data: scene.png, fileExtension: "png") == nil) == readOnly)
            },
            Action("prepareNoteImage(fileAt:)") { readOnly in
                #expect((await model.prepareNoteImage(fileAt: scene.imageSource) == nil) == readOnly)
            },
            Action("commit") { readOnly in
                let prepared = await model.prepareData(Data([1]), fileExtension: "mov", kind: .video, title: "Outro")
                #expect(model.commit(prepared).isEmpty == readOnly)
            },
            // Criação: devolve o valor, mas só o põe no mural quando se pode editar
            Action("createNote") { readOnly in
                let note = model.createNote(into: scene.folder.id)
                #expect(note.kind == .text && note.parentID == scene.folder.id)
                #expect((model.item(id: note.id) == nil) == readOnly)
            },
            Action("createSticky") { readOnly in
                let sticky = model.createSticky()
                #expect(sticky.kind == .sticky)
                #expect((model.item(id: sticky.id) == nil) == readOnly)
            },
            Action("createFolder(named:)") { readOnly in
                let folder = model.createFolder(named: "Ideias")
                #expect(folder.kind == .folder && folder.title == "Ideias")
                #expect((model.item(id: folder.id) == nil) == readOnly)
            },
            Action("createFolder(named:into:)") { readOnly in
                #expect((model.createFolder(named: "Dentro", into: scene.folder.id) == nil) == readOnly)
            },
            Action("createFreeText") { readOnly in
                let freeText = model.createFreeText("Novo")
                #expect(freeText.text == "Novo")
                #expect((model.freeText(id: freeText.id) == nil) == readOnly)
            },
            // Lembretes: automáticos, sem aviso
            Action("updateReminder", warns: false) { readOnly in
                #expect(model.updateReminder(scene.reminder.id, with: changedReminder) == !readOnly)
            },
            Action("markReminderMissing", warns: false) { _ in
                model.markReminderMissing(scene.reminder.id)
            },
            // Edição
            Action("renameFolder") { readOnly in
                #expect(model.renameFolder(scene.folder.id, to: "Outro nome") == !readOnly)
            },
            Action("renameItem") { readOnly in
                #expect(model.renameItem(scene.sticky.id, to: "Outro nome") == !readOnly)
            },
            Action("updateNote") { _ in
                model.updateNote(scene.note.id, title: "Novo", text: "Texto novo")
            },
            Action("toggleNoteTask") { readOnly in
                #expect(model.toggleNoteTask(scene.note.id, segment: 0, in: Self.noteBody) == !readOnly)
            },
            Action("addNoteAttachment") { readOnly in
                #expect(model.addNoteAttachment(attachment, to: scene.note.id) == !readOnly)
            },
            Action("updateSticky") { _ in
                model.updateSticky(scene.sticky.id, text: "Tinta verde", color: .green)
            },
            Action("setColorTag") { readOnly in
                #expect(model.setColorTag(.red, for: scene.sticky.id) == !readOnly)
            },
            Action("setCaption") { _ in
                model.setCaption("Legenda", for: scene.sticky.id)
            },
            Action("toggleChecklistEntry") { _ in
                model.toggleChecklistEntry(scene.entry.id, in: scene.checklist.id)
            },
            Action("updateFreeText") { readOnly in
                #expect(model.updateFreeText(scene.freeText.id, text: "Outro texto") == !readOnly)
            },
            Action("moveFreeText") { readOnly in
                #expect(model.moveFreeText(scene.freeText.id, to: BoardPoint(x: 10, y: 10)) == !readOnly)
            },
            Action("resizeFreeText") { readOnly in
                #expect(model.resizeFreeText(scene.freeText.id, to: BoardSize(width: 400, height: 200)) == !readOnly)
            },
            Action("deleteFreeText") { readOnly in
                #expect(model.deleteFreeText(scene.freeText.id) == !readOnly)
            },
            // Posição e estrutura
            Action("move") { _ in
                model.move(scene.sticky.id, to: BoardPoint(x: 900, y: 900))
            },
            Action("placeInFolder") { _ in
                model.placeInFolder(scene.inner.id, at: BoardPoint(x: 30, y: 30))
            },
            Action("resize") { readOnly in
                #expect(model.resize(scene.sticky.id, to: BoardSize(width: 300, height: 240)) == !readOnly)
            },
            Action("arrange") { readOnly in
                #expect(model.arrange([scene.sticky.id: BoardPoint(x: 900, y: 600)]).isEmpty == readOnly)
            },
            Action("moveIntoFolder") { _ in
                model.moveIntoFolder(scene.sticky.id, folderID: scene.folder.id)
            },
            Action("moveToBoard") { _ in
                model.moveToBoard(scene.inner.id)
            },
            Action("moveUp") { _ in
                model.moveUp(scene.inner.id)
            },
            Action("delete") { _ in
                model.delete(scene.clip.id)
            },
        ]
    }

    /// Roda a ação num mural só para ver e confere que nada mudou (memória, `board.json` e `Items/`) e que a pessoa foi avisada.
    private func expectRefused(_ action: Action, in scene: Scene) async {
        let board = scene.model.board
        let stored = try? scene.store.load()
        let files = storedFiles(scene)
        scene.model.lastError = nil

        await action.run(true)

        #expect(scene.model.board == board, "\(action.name): mudou o mural")
        #expect((try? scene.store.load()) == stored, "\(action.name): gravou no disco")
        #expect(storedFiles(scene) == files, "\(action.name): mexeu em Items/")
        #expect(scene.model.lastError == (action.warns ? Self.message : nil), "\(action.name): aviso ao usuário")
    }

    // MARK: Recusa

    @Test("Todo método que muda o mural é recusado em só leitura e volta a funcionar ao sair dela")
    func everyEditIsRefusedAndFreedAgain() async throws {
        let probe = try makeScene()
        defer { cleanUp(probe) }
        let total = actions(for: probe).count
        #expect(total == 41, "a lista mudou: confira se algum método novo que muda o mural ficou de fora")

        for index in 0..<total {
            let scene = try makeScene()
            defer { cleanUp(scene) }
            let action = actions(for: scene)[index]

            scene.model.isReadOnly = true
            await expectRefused(action, in: scene)

            scene.model.isReadOnly = false
            let board = scene.model.board
            let files = storedFiles(scene)
            scene.model.lastError = nil
            await action.run(false)
            #expect(scene.model.board != board || storedFiles(scene) != files, "\(action.name): não fez nada com o mural editável")
            #expect(scene.model.lastError == nil, "\(action.name): avisou sem precisar")
        }
    }

    @Test("Em só leitura, todas as ações juntas deixam o mural, o disco e Items/ como estavam")
    func allActionsTogetherChangeNothing() async throws {
        let scene = try makeReadOnlyScene()
        defer { cleanUp(scene) }
        let board = scene.model.board
        let stored = try scene.store.load()
        let files = storedFiles(scene)
        let clipFile = scene.model.fileURL(for: scene.clip)
        #expect(exists(clipFile), "controle: o arquivo do clipe existe")

        for action in actions(for: scene) {
            await action.run(true)
        }

        #expect(scene.model.board == board)
        #expect(try scene.store.load() == stored)
        #expect(storedFiles(scene) == files)
        #expect(exists(clipFile), "apagar o clipe foi recusado, e o arquivo continua")
    }

    @Test("Confirmar uma importação já preparada é recusado e apaga os arquivos preparados")
    func commitRefusesAndDiscardsThePreparedFiles() async throws {
        let scene = try makeScene()
        defer { cleanUp(scene) }
        let model = scene.model
        let board = model.board
        let stored = try scene.store.load()
        let files = storedFiles(scene)
        let prepared = await model.prepareData(Data([4, 5, 6]), fileExtension: "mov", kind: .video, title: "Outro clipe")
        let preparedItem = try #require(prepared.items.first)
        let preparedFile = try #require(model.fileURL(for: preparedItem))
        #expect(exists(preparedFile), "controle: o arquivo foi gravado enquanto o mural ainda podia ser editado")

        // A permissão mudou durante a cópia.
        model.isReadOnly = true
        model.lastError = nil
        #expect(model.commit(prepared, into: scene.folder.id).isEmpty)

        #expect(model.lastError == Self.message)
        #expect(model.board == board)
        #expect(model.item(id: preparedItem.id) == nil)
        #expect(try scene.store.load() == stored)
        #expect(!exists(preparedFile), "o arquivo preparado foi apagado")
        #expect(storedFiles(scene) == files, "nenhum arquivo órfão em Items/")
    }

    // MARK: O que continua valendo

    @Test("As frases curtas continuam sendo guardadas, porque são de cada Mac")
    func keySentencesStillWork() throws {
        let scene = try makeReadOnlyScene()
        defer { cleanUp(scene) }
        let record = KeySentenceRecord(source: Self.noteBody, choices: [:])

        #expect(scene.model.setKeySentences(record, for: scene.note.id))

        #expect(scene.model.item(id: scene.note.id)?.keySentences == record)
        #expect(scene.model.lastError == nil)
        #expect(try scene.store.load()?.item(id: scene.note.id)?.keySentences == record, "gravou no disco")
    }

    @Test("Limpar arquivos continua valendo: discard, discardNoteImage e finalizeDeferredDeletions")
    func cleaningFilesStillWorks() async throws {
        let scene = try makeScene()
        defer { cleanUp(scene) }
        let model = scene.model
        let prepared = await model.prepareData(Data([4, 5, 6]), fileExtension: "mov", kind: .video, title: "Outro clipe")
        let preparedFile = try #require(prepared.items.first.flatMap { model.fileURL(for: $0) })
        let attachment = try #require(await model.prepareNoteImage(data: scene.png, fileExtension: "png"))
        let attachmentFile = model.noteImageURL(named: attachment.fileName)
        #expect(exists(preparedFile) && exists(attachmentFile))

        model.isReadOnly = true
        model.discard(prepared)
        model.discardNoteImage(attachment)

        #expect(!exists(preparedFile) && !exists(attachmentFile))
        #expect(model.lastError == nil)

        // A exclusão adiada de antes de ficar só para ver termina com a gravação da sessão, que não depende da permissão.
        let deferred = try makeScene(persistence: .deferred)
        defer { cleanUp(deferred) }
        let first = deferred.model.fileURL(for: deferred.clip)
        deferred.model.delete(deferred.clip.id)
        #expect(exists(first), "controle: a exclusão adiada ainda não apagou o arquivo")
        deferred.model.isReadOnly = true
        deferred.model.finalizeDeferredDeletions()
        #expect(!exists(first))

        // A variante que recebe o mural já gravado.
        deferred.model.isReadOnly = false
        let second = try #require(deferred.model.importData(Data([9]), fileExtension: "mov", kind: .video, title: "Segundo"))
        let secondFile = deferred.model.fileURL(for: second)
        deferred.model.delete(second.id)
        #expect(exists(secondFile), "controle: a exclusão adiada ainda não apagou o arquivo")
        deferred.model.isReadOnly = true
        deferred.model.finalizeDeferredDeletions(persistedBoard: deferred.model.board)
        #expect(!exists(secondFile))
        #expect(deferred.model.lastError == nil)
    }

    @Test("Subir um nível é recusado com aviso, também no cartão que já está solto no mural")
    func moveUpIsRefusedForAnyCard() throws {
        let scene = try makeReadOnlyScene()
        defer { cleanUp(scene) }
        let model = scene.model
        let board = model.board

        for card in [scene.inner, scene.sticky] {
            model.lastError = nil
            model.moveUp(card.id)
            #expect(model.lastError == Self.message)
            #expect(model.board == board)
        }
    }

    @Test("Prévia de link em só leitura: entram os arquivos e o estado, nada do que é compartilhado")
    func linkPreviewsKeepOnlyTheLocalParts() throws {
        let scene = try makeReadOnlyScene()
        defer { cleanUp(scene) }
        let model = scene.model
        let others = model.board.items.filter { $0.id != scene.link.id }
        let fetched = stamp(3_600)
        let update = LinkPreviewUpdate(
            itemID: scene.link.id, pageTitle: "Mac - Apple", siteName: "Apple", summary: "Descrição da página",
            remoteImageURL: URL(string: "https://cdn.apple.com/mac.jpg"), previewImageFile: "capa.jpg", iconFile: "icone.png",
            replacesContent: true, state: .ready(fetchedAt: fetched))

        model.applyLinkPreviews([update])

        var expected = scene.link
        expected.link?.previewImageFile = "capa.jpg"
        expected.link?.iconFile = "icone.png"
        expected.link?.preview = .ready(fetchedAt: fetched)
        #expect(model.item(id: scene.link.id) == expected, "só as partes locais do link mudaram")
        #expect(model.item(id: scene.link.id)?.title == "apple.com", "o título do cartão não vira o da página")
        #expect(model.board.items.filter { $0.id != scene.link.id } == others)
        #expect(model.lastError == nil)
        #expect(try scene.store.load()?.item(id: scene.link.id)?.link?.previewImageFile == "capa.jpg", "gravou no disco")

        // A mesma prévia de novo não é uma alteração; uma falha só muda o estado.
        let afterFirst = model.board
        model.applyLinkPreviews([update])
        #expect(model.board == afterFirst)
        model.applyLinkPreviews([LinkPreviewUpdate(itemID: scene.link.id, state: .failed(at: stamp(7_200), attempts: 2))])
        expected.link?.preview = .failed(at: stamp(7_200), attempts: 2)
        #expect(model.item(id: scene.link.id) == expected)
    }

    @Test("Música em só leitura: entram a capa e o id da biblioteca, nada do que é compartilhado")
    func musicKeepsOnlyTheLocalParts() throws {
        let scene = try makeReadOnlyScene()
        defer { cleanUp(scene) }
        let model = scene.model
        let others = model.board.items.filter { $0.id != scene.music.id }
        var incoming = try #require(scene.music.music)
        incoming.title = "Outro título"
        incoming.subtitle = "Outro artista"
        incoming.trackCount = 99
        incoming.artworkFile = "capa.jpg"
        incoming.libraryID = "L1"

        #expect(model.updateMusic(scene.music.id, with: incoming), "a capa e o id da biblioteca mudaram")

        var expected = scene.music
        expected.music?.artworkFile = "capa.jpg"
        expected.music?.libraryID = "L1"
        #expect(model.item(id: scene.music.id) == expected, "o título do cartão e o do snapshot não mudaram")
        #expect(model.board.items.filter { $0.id != scene.music.id } == others)
        #expect(model.lastError == nil)
        #expect(try scene.store.load()?.item(id: scene.music.id)?.music?.artworkFile == "capa.jpg", "gravou no disco")

        // Repetir não muda nada, e uma mudança só no que é compartilhado também não.
        let afterFirst = model.board
        #expect(!model.updateMusic(scene.music.id, with: incoming))
        var onlyShared = try #require(model.item(id: scene.music.id)?.music)
        onlyShared.subtitle = "Terceiro artista"
        #expect(!model.updateMusic(scene.music.id, with: onlyShared))
        #expect(model.board == afterFirst)
        #expect(model.lastError == nil)
    }

    // MARK: A propriedade

    @Test("isReadOnly começa desligado e é observável: a interface é avisada quando ele muda")
    func isReadOnlyIsObservable() throws {
        let scene = try makeScene()
        defer { cleanUp(scene) }
        let model = scene.model
        #expect(!model.isReadOnly)

        let flag = ChangeFlag()
        withObservationTracking {
            _ = model.isReadOnly
        } onChange: {
            flag.raise()
        }
        #expect(!flag.isRaised)

        model.isReadOnly = true
        #expect(flag.isRaised)
    }
}

/// Marca que o `onChange` da observação foi chamado.
private final class ChangeFlag: Sendable {
    private let raised = Mutex(false)

    var isRaised: Bool { raised.withLock { $0 } }

    func raise() {
        raised.withLock { $0 = true }
    }
}
