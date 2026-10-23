import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import Observation
import os

/// Um mural aberto numa janela: o modelo vivo, que pode ter mudanças ainda não gravadas.
struct LiveBoard {
    let id: BoardID
    let model: BoardModel
}

/// Mantém prontas as capas dos murais para a vitrine.
///
/// A capa de um mural fechado vem do disco (`BoardCoverFiles`) quando a revisão confere; senão é desenhada a partir
/// do mural salvo, gravada com a revisão e mostrada. A capa de um mural aberto numa janela é desenhada do modelo
/// vivo, que pode ter mudanças ainda não gravadas, e por isso não vai para o disco: a revisão em disco não
/// corresponde a ele.
///
/// O trabalho corre numa fila serial, uma capa por vez. Cada desenho ocupa a thread principal só durante o
/// `ImageRenderer`; ler, decodificar, codificar e apagar arquivos acontece fora dela.
@MainActor
@Observable
final class BoardCoverService {
    /// A capa de cada mural que está na memória; a vitrine observa.
    private(set) var images: [BoardID: CGImage] = [:]

    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "Capas")

    /// O que a imagem na memória representa.
    private struct Shown {
        /// A revisão do conteúdo, em disco, de que a imagem vem; `nil` quando foi desenhada de um mural vivo.
        var revision: Int?
        /// O conteúdo do último desenho de um mural vivo, para só redesenhar se ele mudou.
        var liveBoard: Board?
        /// Ordem de uso: quanto maior, mais recente.
        var lastUse: Int
    }

    /// A capa mais recente que o disco tem, já decodificada.
    private nonisolated struct StoredCover: Sendable {
        let revision: Int
        let image: CGImage
    }

    private let library: BoardLibrary
    private let files: BoardCoverFiles
    private let liveBoards: @MainActor () -> [LiveBoard]
    private let linkPreviewFiles: @MainActor (BoardID) -> LinkPreviewFiles?
    private let render: @MainActor (Board, BoardModel, LinkPreviewFiles?) async -> CGImage?
    private let memoryLimit: Int

    @ObservationIgnored private var memory: [BoardID: Shown] = [:]
    @ObservationIgnored private var clock = 0
    /// Os murais do último pedido, na ordem de prioridade, menos os que já foram atendidos.
    @ObservationIgnored private var pending: [BoardLibraryEntry] = []
    @ObservationIgnored private var requestedIDs: Set<BoardID> = []
    @ObservationIgnored private var isDrainScheduled = false
    /// Fim da fila serial: o último trabalho entregue, que o próximo espera terminar.
    @ObservationIgnored private var lane: Task<Void, Never>?
    @ObservationIgnored private var outstandingJobs = 0
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - library: de onde vem o conteúdo dos murais fechados.
    ///   - files: a pasta das capas gravadas.
    ///   - liveBoards: os murais abertos em janelas agora; consultada a cada capa.
    ///   - linkPreviewFiles: a pasta das prévias dos links e das capas de música de um mural.
    ///   - render: quem desenha a capa; os testes trocam por um que conta as chamadas.
    ///   - memoryLimit: quantas imagens ficam na memória; passando disso, saem as menos recentes que o pedido atual
    ///     não inclui.
    init(
        library: BoardLibrary,
        files: BoardCoverFiles,
        liveBoards: @escaping @MainActor () -> [LiveBoard],
        linkPreviewFiles: @escaping @MainActor (BoardID) -> LinkPreviewFiles?,
        render: @escaping @MainActor (Board, BoardModel, LinkPreviewFiles?) async -> CGImage? = BoardCoverRenderer.render,
        memoryLimit: Int = 30
    ) {
        self.library = library
        self.files = files
        self.liveBoards = liveBoards
        self.linkPreviewFiles = linkPreviewFiles
        self.render = render
        self.memoryLimit = memoryLimit
    }

    // MARK: Pedidos

    /// Pede as capas de `entries`. A ordem é a prioridade: a primeira é a mais urgente (a do centro da vitrine).
    /// Um pedido novo substitui o que ainda esperava na fila; a capa que já está sendo feita termina.
    func request(_ entries: [BoardLibraryEntry]) {
        var seen = Set<BoardID>()
        pending = entries.filter { seen.insert($0.manifest.id).inserted }
        requestedIDs = seen
        for id in seen { touch(id) }
        trimMemory()
        if !pending.isEmpty { scheduleDrain() }
    }

    /// Espera a fila esvaziar: pedidos, atualizações e limpezas, inclusive os que chegarem enquanto espera.
    func waitUntilIdle() async {
        guard outstandingJobs > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    /// Faz a capa de `board` de novo depois de um envio: desenha, grava com a revisão dada e mostra. Não lê o disco
    /// e entra na fila serial, atrás do que já está em andamento.
    func refresh(board: Board, model: BoardModel, boardID: BoardID, revision: Int) async {
        let job = enqueue { [self] in
            await drawAndShow(board: board, model: model, boardID: boardID, revision: revision)
        }
        await job.value
    }

    /// Apaga as capas dos murais que não estão em `boardIDs`: da memória e do pedido na hora, do disco na fila, atrás do
    /// que já está em andamento.
    func sweep(keeping boardIDs: Set<BoardID>) {
        pending.removeAll { !boardIDs.contains($0.manifest.id) }
        requestedIDs.formIntersection(boardIDs)
        for id in Array(images.keys) where !boardIDs.contains(id) { forget(id) }
        enqueue { [files] in await Self.sweepCovers(files: files, keeping: boardIDs) }
    }

    // MARK: Fila serial

    /// Coloca um trabalho no fim da fila: ele começa quando o anterior termina.
    @discardableResult
    private func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = lane
        outstandingJobs += 1
        let task = Task { @MainActor [self] in
            await previous?.value
            await work()
            jobFinished()
        }
        lane = task
        return task
    }

    private func jobFinished() {
        outstandingJobs -= 1
        guard outstandingJobs == 0 else { return }
        lane = nil
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Uma capa por trabalho: o que chegar à fila entre uma capa e outra (uma atualização, uma limpeza) passa na frente
    /// da próxima do pedido.
    private func scheduleDrain() {
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        enqueue { [self] in await drainNext() }
    }

    private func drainNext() async {
        isDrainScheduled = false
        guard !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        await process(entry)
        if !pending.isEmpty { scheduleDrain() }
    }

    // MARK: Uma capa

    private func process(_ entry: BoardLibraryEntry) async {
        if let live = liveBoards().first(where: { $0.id == entry.manifest.id }) {
            await drawLive(live)
        } else {
            await loadOrDraw(entry)
        }
    }

    /// Mural aberto: desenha do modelo vivo, só se o conteúdo mudou desde a última capa (ou se não há imagem). Não grava.
    private func drawLive(_ live: LiveBoard) async {
        let board = live.model.board
        if images[live.id] != nil, memory[live.id]?.liveBoard == board {
            touch(live.id)
            return
        }
        guard let image = await render(board, live.model, linkPreviewFiles(live.id)) else {
            Self.log.error("A capa do mural aberto \(live.id.description, privacy: .public) não foi desenhada")
            return
        }
        show(image, for: live.id, revision: nil, liveBoard: board)
    }

    /// Mural fechado: usa a imagem da memória ou a capa do disco se a revisão confere; senão desenha de novo.
    private func loadOrDraw(_ entry: BoardLibraryEntry) async {
        let id = entry.manifest.id
        let revision = entry.manifest.contentRevision

        // Uma imagem de revisão igual ou mais nova serve: o pedido pode ter sido feito antes de um `refresh`.
        if let known = memory[id]?.revision, known >= revision, images[id] != nil {
            touch(id)
            return
        }

        let stored = await Self.readStoredCover(files: files, boardID: id)
        if let stored, stored.revision == revision {
            show(stored.image, for: id, revision: revision)
            return
        }
        // Só há capa velha: aparece já, no lugar do vazio, enquanto a nova é desenhada.
        if let stored, images[id] == nil {
            show(stored.image, for: id, revision: stored.revision)
        }

        guard let (board, package) = await readBoard(of: entry) else { return }
        let model = BoardModel(board: board, store: BoardStore(directory: package), persistence: .deferred)
        await drawAndShow(board: board, model: model, boardID: id, revision: revision)
    }

    /// O conteúdo salvo do mural e o pacote onde ele está. Falha de leitura é registrada e deixa o mural sem capa nova.
    private func readBoard(of entry: BoardLibraryEntry) async -> (Board, URL)? {
        let id = entry.manifest.id
        do {
            guard let board = try await library.readBoard(entry.route) else {
                Self.log.error("O mural \(id.description, privacy: .public) não tem conteúdo para a capa")
                return nil
            }
            let repository = try await library.repository(for: entry.route)
            return (board, await repository.packageURL(for: id))
        } catch {
            Self.log.error(
                "Não foi possível ler o mural \(id.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Desenha, grava com a revisão (fora da thread principal) e mostra.
    private func drawAndShow(board: Board, model: BoardModel, boardID: BoardID, revision: Int) async {
        guard let image = await render(board, model, linkPreviewFiles(boardID)) else {
            Self.log.error("A capa do mural \(boardID.description, privacy: .public) não foi desenhada")
            return
        }
        do {
            try await Self.storeCover(image, files: files, boardID: boardID, revision: revision)
        } catch {
            Self.log.error(
                "Não foi possível gravar a capa de \(boardID.description, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        // A imagem vale mesmo que a gravação tenha falhado: só a próxima abertura do app a desenha de novo.
        show(image, for: boardID, revision: revision)
    }

    // MARK: Memória

    private func show(_ image: CGImage, for id: BoardID, revision: Int?, liveBoard: Board? = nil) {
        images[id] = image
        memory[id] = Shown(revision: revision, liveBoard: liveBoard, lastUse: nextTick())
        trimMemory()
    }

    private func touch(_ id: BoardID) {
        guard memory[id] != nil else { return }
        memory[id]?.lastUse = nextTick()
    }

    private func nextTick() -> Int {
        clock += 1
        return clock
    }

    private func forget(_ id: BoardID) {
        images[id] = nil
        memory[id] = nil
    }

    /// Passando de `memoryLimit` imagens, descarta as menos recentes que o pedido atual não inclui.
    private func trimMemory() {
        guard images.count > memoryLimit else { return }
        let leastRecentFirst = images.keys
            .filter { !requestedIDs.contains($0) }
            .sorted { (memory[$0]?.lastUse ?? 0) < (memory[$1]?.lastUse ?? 0) }
        for id in leastRecentFirst where images.count > memoryLimit {
            forget(id)
        }
    }

    // MARK: Disco, fora da thread principal

    /// A capa mais recente do mural no disco, decodificada na hora para a vitrine não decodificar ao desenhar.
    @concurrent
    private nonisolated static func readStoredCover(files: BoardCoverFiles, boardID: BoardID) async -> StoredCover? {
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let cover = files.latest(for: boardID),
            let source = CGImageSourceCreateWithURL(cover.url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return StoredCover(revision: cover.revision, image: image)
    }

    @concurrent
    private nonisolated static func storeCover(_ image: CGImage, files: BoardCoverFiles, boardID: BoardID, revision: Int) async throws {
        try files.store(image, for: boardID, revision: revision)
    }

    @concurrent
    private nonisolated static func sweepCovers(files: BoardCoverFiles, keeping boardIDs: Set<BoardID>) async {
        files.sweep(keeping: boardIDs)
    }
}
