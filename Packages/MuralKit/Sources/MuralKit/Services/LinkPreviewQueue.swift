import Foundation

/// Fila das buscas de prévia de links: limita as buscas simultâneas e as por host, grava os arquivos de cada
/// resultado e entrega os resultados em lotes para a interface atualizar o mural poucas vezes.
///
/// O buscador é injetado (`LinkPreviewFetching`), então a fila funciona sem rede nos testes.
public actor LinkPreviewQueue {
    private let fetcher: any LinkPreviewFetching
    private let files: LinkPreviewFiles
    private let maxConcurrent: Int
    private let maxPerHost: Int
    private let batchDelay: Duration
    private let now: @Sendable () -> Date
    private let deliver: @Sendable ([LinkPreviewUpdate]) async -> Void

    /// Pedidos esperando vaga, na ordem de chegada.
    private var waiting: [LinkPreviewRequest] = []
    /// Cartões na fila, em busca ou com resultado ainda não entregue; um cartão entra uma vez só.
    private var tracked: Set<UUID> = []
    private var running: [UUID: Task<Void, Never>] = [:]
    private var runningPerHost: [String: Int] = [:]
    /// Resultados prontos, esperando o próximo `deliver`.
    private var batch: [LinkPreviewUpdate] = []
    /// Presente enquanto há um lote esperando o prazo ou sendo entregue.
    private var deliveryTask: Task<Void, Never>?
    /// Muda a cada `cancelAll()`: o que uma busca ou entrega antiga ainda tentar fazer é descartado.
    private var epoch = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - fetcher: faz a busca de cada página.
    ///   - files: onde as imagens e os ícones são gravados.
    ///   - maxConcurrent: buscas ao mesmo tempo, no total.
    ///   - maxPerHost: buscas ao mesmo tempo no mesmo host (`WebLink.displayHost`).
    ///   - batchDelay: espera, depois do primeiro resultado de um lote, para juntar os que chegarem; com `.zero` entrega logo.
    ///   - now: relógio, trocável nos testes.
    ///   - deliver: recebe cada lote de resultados.
    public init(
        fetcher: any LinkPreviewFetching,
        files: LinkPreviewFiles,
        maxConcurrent: Int = 4,
        maxPerHost: Int = 2,
        batchDelay: Duration = .milliseconds(750),
        now: @escaping @Sendable () -> Date = { .now },
        deliver: @escaping @Sendable ([LinkPreviewUpdate]) async -> Void
    ) {
        self.fetcher = fetcher
        self.files = files
        self.maxConcurrent = max(1, maxConcurrent)
        self.maxPerHost = max(1, maxPerHost)
        self.batchDelay = batchDelay
        self.now = now
        self.deliver = deliver
    }

    /// Verdadeiro quando não há pedido esperando, busca em andamento nem resultado por entregar.
    public var isIdle: Bool {
        waiting.isEmpty && running.isEmpty && batch.isEmpty && deliveryTask == nil
    }

    /// Espera a fila ficar ociosa: tudo buscado e entregue, ou cancelado.
    public func waitUntilIdle() async {
        guard !isIdle else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    /// Põe pedidos na fila, na ordem recebida. Um cartão já esperando, em busca ou com o resultado ainda
    /// por entregar é ignorado.
    public func enqueue(_ requests: [LinkPreviewRequest]) {
        for request in requests {
            guard tracked.insert(request.itemID).inserted else { continue }
            waiting.append(request)
        }
        startFetches()
    }

    /// Esvazia a fila, cancela as buscas em andamento e descarta o lote não entregue. Nada é entregue depois,
    /// e a fila pode ser usada de novo.
    public func cancelAll() {
        epoch += 1
        waiting.removeAll()
        for task in running.values { task.cancel() }
        running.removeAll()
        runningPerHost.removeAll()
        tracked.removeAll()
        batch.removeAll()
        deliveryTask?.cancel()
        deliveryTask = nil
        resumeIdleWaitersIfIdle()
    }

    // MARK: Buscas

    /// Inicia pedidos, do mais antigo ao mais novo, enquanto houver vaga; pula os de host que já está cheio.
    private func startFetches() {
        var position = 0
        while running.count < maxConcurrent, position < waiting.count {
            let request = waiting[position]
            let host = WebLink.displayHost(of: request.url)
            guard runningPerHost[host, default: 0] < maxPerHost else {
                position += 1
                continue
            }
            waiting.remove(at: position)
            start(request, host: host)
        }
    }

    private func start(_ request: LinkPreviewRequest, host: String) {
        runningPerHost[host, default: 0] += 1
        let epoch = self.epoch
        let fetcher = self.fetcher
        let files = self.files
        let clock = self.now
        running[request.itemID] = Task.detached(priority: .utility) { [self] in
            let update = await Self.fetch(request, fetcher: fetcher, files: files, now: clock)
            await finish(request, host: host, update: update, epoch: epoch)
        }
    }

    /// Busca a prévia e grava os arquivos. Falha de busca ou de gravação vira um resultado `.failed`;
    /// cancelamento não gera resultado.
    private static func fetch(
        _ request: LinkPreviewRequest, fetcher: any LinkPreviewFetching, files: LinkPreviewFiles, now: @Sendable () -> Date
    ) async -> LinkPreviewUpdate? {
        do {
            let fetched = try await fetcher.fetchPreview(for: request)
            try Task.checkCancellation()
            let names = try files.store(imageData: fetched.imageData, iconData: fetched.iconData, for: request.itemID)
            return LinkPreviewUpdate(
                itemID: request.itemID, pageTitle: fetched.title, siteName: fetched.siteName, summary: fetched.summary,
                remoteImageURL: fetched.remoteImageURL, previewImageFile: names.image, iconFile: names.icon,
                replacesContent: request.isRefresh, state: .ready(fetchedAt: now()))
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            return LinkPreviewUpdate(itemID: request.itemID, state: .failed(at: now(), attempts: request.previousAttempts + 1))
        }
    }

    private func finish(_ request: LinkPreviewRequest, host: String, update: LinkPreviewUpdate?, epoch: Int) {
        // `cancelAll()` já zerou a contabilidade desta busca.
        guard epoch == self.epoch else { return }
        running[request.itemID] = nil
        runningPerHost[host, default: 1] -= 1
        if runningPerHost[host] == 0 { runningPerHost[host] = nil }

        if let update {
            batch.append(update)
            scheduleDelivery()
        } else {
            tracked.remove(request.itemID)
        }
        startFetches()
        resumeIdleWaitersIfIdle()
    }

    // MARK: Entrega

    private func scheduleDelivery() {
        guard deliveryTask == nil else { return }
        let epoch = self.epoch
        deliveryTask = Task { await runDeliveries(epoch: epoch) }
    }

    /// Entrega um lote `batchDelay` depois do primeiro resultado dele. Resultados que chegam durante a entrega
    /// formam o lote seguinte, que espera o prazo de novo.
    private func runDeliveries(epoch: Int) async {
        while epoch == self.epoch, !batch.isEmpty {
            if batchDelay > .zero {
                do { try await Task.sleep(for: batchDelay) } catch { return }
            }
            guard epoch == self.epoch else { return }
            let updates = batch
            batch.removeAll()
            await deliver(updates)
            guard epoch == self.epoch else { return }
            for update in updates { tracked.remove(update.itemID) }
        }
        guard epoch == self.epoch else { return }
        deliveryTask = nil
        resumeIdleWaitersIfIdle()
    }

    private func resumeIdleWaitersIfIdle() {
        guard isIdle else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
