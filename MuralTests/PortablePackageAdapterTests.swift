import Foundation
import MuralKit
import PhotosUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Mural

private enum CleanupGateError: Error {
    case injectedFailure
}

private actor CleanupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var failuresRemaining = 1

    func wait() async throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CleanupGateError.injectedFailure
        }
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Adaptador do pacote portátil")
@MainActor
struct PortablePackageAdapterTests {
    @Test("UTType do mural é um package exportado")
    func packageTypeIsExportedPackage() {
        #expect(UTType.muralPackage.identifier == "com.joaocosta.mural")
        #expect(UTType.muralPackage.tags[.filenameExtension] == ["mural"])
    }

    @Test("snapshot é leve e aponta para o staging imutável")
    func snapshotUsesStagingURL() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).mural", isDirectory: true)
        let document = MuralPackageDocument(stagingURL: url)
        let snapshot = try await document.snapshot(contentType: .muralPackage)
        #expect(snapshot.stagingURL == url.standardizedFileURL)
    }

    @Test("ações capturam mural, apresentação e pasta antes do painel")
    func importDestinationIsStable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("actions-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Destino")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        let folderID = UUID()
        session.beginFileImport(folderID: folderID)

        #expect(
            session.importDestination
                == BoardImportDestination(
                    route: route,
                    boardID: session.boardID,
                    presentationEpoch: session.presentationEpoch,
                    folderID: folderID))
    }

    @Test("security scope fica aberto até o fim da operação assíncrona")
    func asyncSecurityScopeLifetime() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString)")
        var events: [String] = []

        try await SecurityScopedAccess.withAccess(
            to: [url],
            start: { _ in
                events.append("start")
                return true
            },
            stop: { _ in events.append("stop") },
            operation: {
                #expect(events == ["start"])
                try await Task.sleep(for: .milliseconds(1))
                #expect(events == ["start"])
            })

        #expect(events == ["start", "stop"])
    }

    @Test("época do painel sobrevive a autosave e rejeita sessão obsoleta")
    func importPanelEpochIsIndependentFromGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("panel-epoch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Destino")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        let model = try #require(session.model)
        let initialGeneration = session.generation
        session.beginFileImport(folderID: nil)
        let panelEpoch = session.presentationEpoch

        _ = model.importText("autosave")
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()
        #expect(session.generation > initialGeneration)
        #expect(session.importDestination?.presentationEpoch == panelEpoch)

        let source = directory.appendingPathComponent("after-autosave.txt")
        try Data("after".utf8).write(to: source)
        await session.importFiles(from: [source])
        #expect(model.rootItems.contains { $0.title == "after-autosave" })

        session.beginFileImport(folderID: nil)
        session.invalidatePresentation()
        await session.importFiles(from: [source])
        #expect(session.error?.contains("descartada") == true)
    }

    @Test("PhotosPicker captura destino, pasta e âncora antes da seleção")
    func photoImportDestinationIsStable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-destination-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Fotos")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        let folder = try #require(session.model?.createFolder(named: "Viagem"))
        let anchor = BoardPoint(x: 480, y: 320)
        session.zoom.viewport = CGSize(width: 900, height: 700)
        session.zoom.visibleRect = CGRect(x: 120, y: 80, width: 900, height: 700)
        session.zoom.configure(workspace: CanvasWorkspaceState(confirmedZoom: 1, logicalCenter: anchor))
        session.beginPhotoImport(folderID: folder.id)

        let captured = try #require(session.importDestination)
        #expect(captured.route == route)
        #expect(captured.boardID == session.boardID)
        #expect(captured.folderID == folder.id)
        #expect(captured.anchor != nil)
        #expect(captured.presentationEpoch == session.presentationEpoch)
    }

    @Test("PhotosPicker sem representação compatível produz falha explícita")
    func photoImportReportsUnsupportedItem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Fotos")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        session.beginPhotoImport()
        await session.importPhotos([PhotosPickerItem(itemIdentifier: "fake")])

        #expect(session.model?.lastError?.contains("Item 1") == true)
        #expect(session.importDestination == nil)
    }

    @Test("pasta capturada que deixou de existir não recebe arquivos")
    func importRejectsMissingCapturedFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-folder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Destino")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        let source = directory.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: source)
        session.beginFileImport(folderID: UUID())
        await session.importFiles(from: [source])
        #expect(session.error == "A pasta selecionada não existe mais neste mural.")
    }

    @Test("callback antigo não limpa a exportação nova e busy desabilita cópia")
    func exportOperationIDsProtectStaging() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-operations-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Exportação")
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()

        session.beginSaveCopy()
        session.beginSaveCopy()
        for _ in 0..<100 where session.exportTransfer == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = try #require(session.exportTransfer)
        #expect(!session.actions.canSaveCopy)
        await session.finishSaveCopy(nil, operationID: first.operationID)

        session.beginSaveCopy()
        for _ in 0..<100 where session.exportTransfer == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let second = try #require(session.exportTransfer)
        #expect(second.operationID != first.operationID)
        await session.finishSaveCopy(nil, operationID: first.operationID)
        #expect(session.exportTransfer?.operationID == second.operationID)
        await session.finishSaveCopy(nil, operationID: second.operationID)
        #expect(session.exportTransfer == nil)
    }

    @Test("promoção invalida o resume do draft")
    func promotionDisablesDraftResume() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-resume-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        let route = BoardRoute.welcomeDraft(state.stableWelcomeID)
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        await session.load()
        _ = try #require(await session.promoteDraft(named: "Promovido"))
        #expect(try await library.lifecycleState()?.lifecycle == .promoted)
        await #expect(throws: BoardLibraryError.self) {
            _ = try await library.open(route)
        }
    }

    @Test("Finder/Open With usa o mesmo import-as-copy")
    func externalImportIsCopiedIntoLibrary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let sourceRoute = try await library.createNamedBoard("Fonte")
        let package = try await library.exportPackage(sourceRoute)
        let result = try await MuralPackageImport.importAsCopy(from: package, using: library)
        #expect(result.route != sourceRoute)
        #expect(FileManager.default.fileExists(atPath: package.path))
        try await library.cleanupTransfer(package)
    }

    @Test("begin durante cleanup não substitui o staging em finalização")
    func beginSaveCopyIsBlockedDuringCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Exportação")
        let gate = CleanupGate()
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library),
            cleanupTransfer: { _ in try await gate.wait() })
        await session.load()
        session.beginSaveCopy()
        for _ in 0..<100 where session.exportTransfer == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let transfer = try #require(session.exportTransfer)
        await session.finishSaveCopy(.success(directory.appendingPathComponent("saved.mural")), operationID: transfer.operationID)
        #expect(session.exportTransfer?.operationID == transfer.operationID)
        #expect(!session.actions.canSaveCopy)
        #expect(session.error?.contains("limpar") == true)

        // The public menu action retries cleanup using the retained operation
        // ID. The latch is already released, so this cannot suspend forever.
        await gate.release()
        session.actions.retryFlush()
        for _ in 0..<100 where session.exportTransfer != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.exportTransfer == nil)
        #expect(session.exportDocument == nil)
        #expect(session.actions.canSaveCopy)

        session.beginSaveCopy()
        for _ in 0..<100 where session.exportTransfer == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let replacement = try #require(session.exportTransfer)
        await session.finishSaveCopy(nil, operationID: replacement.operationID)
    }
}
