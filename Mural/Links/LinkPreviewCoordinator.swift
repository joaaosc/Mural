import Foundation
import MuralKit
import SwiftUI

extension EnvironmentValues {
    /// Coordenador das prévias de link da janela de mural aberta; `nil` fora de uma janela de mural e
    /// durante o instante em que a janela ainda o está criando.
    @Entry var linkPreviewCoordinator: LinkPreviewCoordinator? = nil
}

/// Um por janela de mural: busca as prévias dos cartões de link e as aplica ao mural.
///
/// Os pedidos vão para uma `LinkPreviewQueue` (que limita as buscas simultâneas e por host e grava os arquivos);
/// cada lote de resultados é aplicado ao `BoardModel` na thread principal. A pasta dos arquivos de prévia é
/// varrida ao começar e alguns segundos depois de cada entrega, fora da thread principal.
@MainActor
final class LinkPreviewCoordinator {
    private let model: BoardModel
    private let files: LinkPreviewFiles
    private let fetcher: any LinkPreviewFetching
    private let batchDelay: Duration
    private let sweepDelay: Duration
    private let sweepMinimumAge: TimeInterval

    /// Criada na primeira vez que é usada, porque o `deliver` dela precisa de `self`.
    private lazy var queue = LinkPreviewQueue(
        fetcher: fetcher, files: files, batchDelay: batchDelay,
        deliver: { [weak self] updates in await self?.deliver(updates) })

    /// Última chamada à fila: cada nova espera a anterior, então um cancelamento nunca passa na frente de um pedido.
    private var lastOperation: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?

    /// - Parameters:
    ///   - model: o mural da janela, que recebe os resultados.
    ///   - files: a pasta das imagens e dos ícones de prévia deste mural.
    ///   - fetcher: quem busca cada página.
    ///   - batchDelay: espera, depois do primeiro resultado, para juntar os que chegarem num lote só.
    ///   - sweepDelay: espera, depois de uma entrega, até varrer a pasta.
    ///   - sweepMinimumAge: idade mínima, em segundos, de um arquivo sem uso para ser apagado.
    init(
        model: BoardModel, files: LinkPreviewFiles, fetcher: any LinkPreviewFetching,
        batchDelay: Duration = .milliseconds(750), sweepDelay: Duration = .seconds(5), sweepMinimumAge: TimeInterval = 600
    ) {
        self.model = model
        self.files = files
        self.fetcher = fetcher
        self.batchDelay = batchDelay
        self.sweepDelay = sweepDelay
        self.sweepMinimumAge = sweepMinimumAge
        scheduleSweep(after: .zero)
    }

    /// Busca a prévia dos cartões de link indicados. Sem `force`, cartões com prévia pronta ou com falha
    /// recente ficam de fora (política do domínio), exceto os de prévia pronta cujo arquivo de imagem ou de
    /// ícone não está mais na pasta; com `force`, todos os cartões de link entram.
    func request(_ itemIDs: [UUID], force: Bool = false) {
        let requests = model.linkPreviewRequests(for: itemIDs, force: force, fileExists: { files.existingURL(for: $0) != nil })
        guard !requests.isEmpty else { return }
        perform { await $0.enqueue(requests) }
    }

    /// Cancela as buscas em andamento e descarta os resultados ainda não aplicados. O coordenador pode
    /// receber novos pedidos depois.
    func cancelAll() {
        sweepTask?.cancel()
        sweepTask = nil
        perform { await $0.cancelAll() }
    }

    /// Espera os pedidos feitos até aqui serem buscados e aplicados e a varredura agendada terminar.
    func waitUntilIdle() async {
        await lastOperation?.value
        await queue.waitUntilIdle()
        await sweepTask?.value
    }

    // MARK: Fila

    private func perform(_ operation: @escaping @Sendable (LinkPreviewQueue) async -> Void) {
        let queue = self.queue
        let previous = lastOperation
        lastOperation = Task {
            await previous?.value
            await operation(queue)
        }
    }

    private func deliver(_ updates: [LinkPreviewUpdate]) {
        model.applyLinkPreviews(updates)
        scheduleSweep(after: sweepDelay)
    }

    // MARK: Varredura

    /// Agenda a varredura, trocando a que ainda esperava: entregas seguidas viram uma varredura só.
    private func scheduleSweep(after delay: Duration) {
        sweepTask?.cancel()
        let files = self.files
        let minimumAge = sweepMinimumAge
        sweepTask = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            // Os nomes em uso são lidos só agora, já com a entrega aplicada.
            guard let referenced = self?.model.referencedLinkPreviewFiles else { return }
            await Self.sweep(files, keeping: referenced, minimumAge: minimumAge)
        }
    }

    @concurrent
    private nonisolated static func sweep(_ files: LinkPreviewFiles, keeping referenced: Set<String>, minimumAge: TimeInterval) async {
        files.sweep(keeping: referenced, minimumAge: minimumAge)
    }
}
