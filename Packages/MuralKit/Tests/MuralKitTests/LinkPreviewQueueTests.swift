import Foundation
import Testing

@testable import MuralKit

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Buscador falso: cada busca fica parada até o teste liberá-la e registra quantas rodaram ao mesmo tempo.
private actor GatedFetcher: LinkPreviewFetching {
    private(set) var started: [LinkPreviewRequest] = []
    private(set) var finishedCount = 0
    private(set) var peakActive = 0
    private(set) var peakPerHost: [String: Int] = [:]

    private var active = 0
    private var activePerHost: [String: Int] = [:]
    private var gates: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<UUID> = []
    private var releasesEverything = false
    private var outcomes: [UUID: Result<FetchedLinkPreview, any Error>] = [:]

    func setOutcome(_ outcome: Result<FetchedLinkPreview, any Error>, for id: UUID) {
        outcomes[id] = outcome
    }

    func fetchPreview(for request: LinkPreviewRequest) async throws -> FetchedLinkPreview {
        let host = WebLink.displayHost(of: request.url)
        started.append(request)
        active += 1
        peakActive = max(peakActive, active)
        activePerHost[host, default: 0] += 1
        peakPerHost[host] = max(peakPerHost[host] ?? 0, activePerHost[host] ?? 0)

        if !releasesEverything, !released.contains(request.itemID) {
            await withCheckedContinuation { gates[request.itemID] = $0 }
        }

        active -= 1
        activePerHost[host, default: 1] -= 1
        finishedCount += 1
        return try (outcomes[request.itemID] ?? .success(FetchedLinkPreview(title: "Título de \(host)"))).get()
    }

    func release(_ id: UUID) {
        released.insert(id)
        gates.removeValue(forKey: id)?.resume()
    }

    func releaseAll() {
        releasesEverything = true
        let waiting = gates.values
        gates.removeAll()
        for gate in waiting { gate.resume() }
    }
}

/// Guarda os lotes que a fila entregou, na ordem.
private actor Deliveries {
    private(set) var batches: [[LinkPreviewUpdate]] = []

    func add(_ updates: [LinkPreviewUpdate]) {
        batches.append(updates)
    }

    var updates: [LinkPreviewUpdate] { batches.flatMap { $0 } }
}

/// Bandeira que o teste levanta quando algo acontece.
private actor Flag {
    private(set) var isRaised = false

    func raise() {
        isRaised = true
    }
}

/// A fila, o buscador falso e a pasta de arquivos de um teste.
private struct Harness {
    let fetcher = GatedFetcher()
    let deliveries = Deliveries()
    let files: LinkPreviewFiles
    let queue: LinkPreviewQueue

    /// - Parameter sleeper: com ele, a espera do lote só termina quando o teste a libera; sem ele, é a espera real.
    init(
        maxConcurrent: Int = 4, maxPerHost: Int = 2, batchDelay: Duration = .zero, filesDirectory: URL? = nil,
        sleeper: ManualSleeper? = nil
    ) {
        let fetcher = fetcher
        let deliveries = deliveries
        let files = LinkPreviewFiles(
            directory: filesDirectory
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("MuralQueue-\(UUID().uuidString)", isDirectory: true))
        self.files = files
        let sleep: @Sendable (Duration) async throws -> Void
        if let sleeper {
            sleep = { _ in try await sleeper.sleep() }
        } else {
            sleep = { try await Task.sleep(for: $0) }
        }
        queue = LinkPreviewQueue(
            fetcher: fetcher, files: files, maxConcurrent: maxConcurrent, maxPerHost: maxPerHost, batchDelay: batchDelay,
            now: { fixedNow }, sleep: sleep, deliver: { await deliveries.add($0) })
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: files.directory)
    }

    func request(_ host: String, _ number: Int = 0, attempts: Int = 0, image: String? = nil, isRefresh: Bool = false) -> LinkPreviewRequest
    {
        LinkPreviewRequest(
            itemID: UUID(), url: URL(string: "https://\(host)/pagina-\(number)")!, remoteImageURL: image.flatMap { URL(string: $0) },
            previousAttempts: attempts, isRefresh: isRefresh)
    }

    /// Espera a fila ficar ociosa, com prazo: um travamento vira falha do teste em vez de travar a suíte.
    func settle() async {
        await waitUntil("a fila ficar ociosa") { await queue.isIdle }
    }

    /// Espera a `count`-ésima busca começar.
    func waitForStarts(_ count: Int) async {
        await waitUntil("\(count) buscas começarem") { await fetcher.started.count >= count }
    }
}

/// Espera o lote ter `count` resultados E a entrega estar parada no prazo: liberar antes disso não acharia ninguém esperando.
private func waitUntilBatchWaits(_ harness: Harness, _ sleeper: ManualSleeper, count: Int) async {
    await waitUntil("\(count) resultados esperando o prazo do lote") {
        let pending = await harness.queue.undeliveredCount
        let sleeping = await sleeper.waitingCount
        return pending == count && sleeping == 1
    }
}

@Suite("Fila de prévias de links")
struct LinkPreviewQueueTests {
    // MARK: Limites

    @Test("Nunca mais de 4 buscas ao mesmo tempo nem de 2 por host, e todos os pedidos são atendidos")
    func respectsGlobalAndPerHostLimits() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let hosts = ["a.example.com", "b.example.com", "c.example.com"]
        let requests = (0..<12).map { harness.request(hosts[$0 % 3], $0) }
        await harness.queue.enqueue(requests)

        // Libera uma por vez, na ordem em que começaram: cada liberação abre uma vaga para a seguinte.
        for released in 0..<requests.count {
            await harness.waitForStarts(released + 1)
            await harness.fetcher.release(await harness.fetcher.started[released].itemID)
        }
        await harness.settle()

        #expect(await harness.fetcher.peakActive == 4)
        let perHost = await harness.fetcher.peakPerHost
        #expect(perHost.keys.sorted() == hosts)
        #expect(perHost.values.allSatisfy { $0 <= 2 })
        #expect(perHost["a.example.com"] == 2)
        #expect(await harness.fetcher.started.count == 12)
        let delivered = await harness.deliveries.updates
        #expect(Set(delivered.map(\.itemID)) == Set(requests.map(\.itemID)) && delivered.count == 12)
    }

    @Test("Com um host só, o limite por host manda: duas buscas por vez mesmo com 4 vagas")
    func perHostLimitBindsWithASingleHost() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let requests = (0..<6).map { harness.request("WWW.Example.com", $0) }
        await harness.queue.enqueue(requests)

        await harness.waitForStarts(2)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await harness.fetcher.started.count == 2, "www. e maiúsculas contam como o mesmo host")

        await harness.fetcher.releaseAll()
        await harness.settle()
        #expect(await harness.fetcher.peakActive == 2)
        #expect(await harness.fetcher.started.count == 6)
    }

    @Test("Pedido de host cheio é pulado, os seguintes passam, e a ordem de chegada vale dentro de cada host")
    func busyHostsAreSkippedKeepingArrivalOrder() async {
        let harness = Harness(maxConcurrent: 3, maxPerHost: 2)
        defer { harness.cleanup() }
        let a = (0..<4).map { harness.request("a.example.com", $0) }
        let b = harness.request("b.example.com")
        let c = harness.request("c.example.com")
        await harness.queue.enqueue(a + [b, c])

        // a0 e a1 enchem o host a; a2 e a3 são puladas; b ocupa a terceira vaga; c espera vaga.
        await harness.waitForStarts(3)
        #expect(Set(await harness.fetcher.started.map(\.itemID)) == [a[0].itemID, a[1].itemID, b.itemID])

        // b termina: o host a continua cheio, então c (e não a2) ocupa a vaga.
        await harness.fetcher.release(b.itemID)
        await harness.waitForStarts(4)
        #expect(await harness.fetcher.started.last?.itemID == c.itemID)

        // a0 termina: o host a abre uma vaga, que vai para a2 (a mais antiga), não para a3.
        await harness.fetcher.release(a[0].itemID)
        await harness.waitForStarts(5)
        #expect(await harness.fetcher.started.last?.itemID == a[2].itemID)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await harness.fetcher.started.count == 5)

        await harness.fetcher.releaseAll()
        await harness.settle()
        #expect(await harness.fetcher.started.count == 6)
        #expect(await harness.fetcher.started.last?.itemID == a[3].itemID)
    }

    @Test("Limites zero ou negativos viram 1 e não travam a fila")
    func nonPositiveLimitsAreClamped() async {
        let harness = Harness(maxConcurrent: 0, maxPerHost: -3)
        defer { harness.cleanup() }
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([
            harness.request("a.example.com", 1), harness.request("b.example.com", 2), harness.request("a.example.com", 3),
        ])
        await harness.settle()

        #expect(await harness.fetcher.peakActive == 1)
        #expect(await harness.deliveries.updates.count == 3)
    }

    // MARK: Repetidos

    @Test("O mesmo cartão enfileirado duas vezes é buscado uma vez, esperando vaga ou em andamento")
    func sameCardIsFetchedOnce() async {
        let harness = Harness(maxConcurrent: 1)
        defer { harness.cleanup() }
        let first = harness.request("a.example.com", 1)
        let second = harness.request("b.example.com", 2)

        await harness.queue.enqueue([first, first, second, second])
        await harness.queue.enqueue([first, second])
        await harness.waitForStarts(1)
        await harness.queue.enqueue([first])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await harness.fetcher.started.map(\.itemID) == [first.itemID])

        await harness.fetcher.releaseAll()
        await harness.settle()
        #expect(await harness.fetcher.started.map(\.itemID) == [first.itemID, second.itemID])
        #expect(await harness.deliveries.updates.map(\.itemID) == [first.itemID, second.itemID])
    }

    @Test("Depois de entregue, o cartão pode ser buscado de novo")
    func deliveredCardCanBeFetchedAgain() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com")
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()
        await harness.queue.enqueue([request])
        await harness.settle()

        #expect(await harness.fetcher.started.count == 2)
        #expect(await harness.deliveries.updates.count == 2)
    }

    // MARK: Resultados

    @Test("Busca bem-sucedida grava a imagem e o ícone e entrega os campos buscados com .ready")
    func successStoresFilesAndBuildsReadyUpdate() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com", image: "https://a.example.com/capa.jpg")
        let remote = try #require(URL(string: "https://a.example.com/og.jpg"))
        await harness.fetcher.setOutcome(
            .success(
                FetchedLinkPreview(
                    title: "Título", siteName: "Site", summary: "Resumo", remoteImageURL: remote,
                    imageData: try TestImages.png(width: 1_200, height: 600), iconData: try TestImages.png(width: 128, height: 128))),
            for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()

        let update = try #require(await harness.deliveries.updates.first)
        #expect(await harness.deliveries.updates.count == 1)
        #expect(update.itemID == request.itemID)
        #expect(update.pageTitle == "Título" && update.siteName == "Site" && update.summary == "Resumo")
        #expect(update.remoteImageURL == remote)
        #expect(update.state == .ready(fetchedAt: fixedNow))

        let imageName = try #require(update.previewImageFile)
        let iconName = try #require(update.iconFile)
        let image = try Data(contentsOf: try #require(harness.files.url(for: imageName)))
        let icon = try Data(contentsOf: try #require(harness.files.url(for: iconName)))
        #expect(TestImages.typeIdentifier(of: image) == "public.jpeg" && TestImages.size(of: image)?.width == 800)
        #expect(TestImages.typeIdentifier(of: icon) == "public.png" && TestImages.size(of: icon)?.width == 64)
    }

    @Test("Pedido de atualização chega ao buscador como tal e o resultado vem marcado para substituir o conteúdo")
    func refreshRequestsProduceReplacingUpdates() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let refresh = harness.request("a.example.com", 1, image: "https://a.example.com/antiga.jpg", isRefresh: true)
        let plain = harness.request("b.example.com", 2)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([refresh, plain])
        await harness.settle()

        let started = await harness.fetcher.started
        #expect(started.first { $0.itemID == refresh.itemID }?.isRefresh == true)
        #expect(started.first { $0.itemID == refresh.itemID }?.remoteImageURL?.absoluteString == "https://a.example.com/antiga.jpg")
        #expect(started.first { $0.itemID == plain.itemID }?.isRefresh == false)
        let updates = await harness.deliveries.updates
        #expect(updates.first { $0.itemID == refresh.itemID }?.replacesContent == true)
        #expect(updates.first { $0.itemID == plain.itemID }?.replacesContent == false)
    }

    @Test("Sem imagem nem ícone, o resultado vem só com os textos e nada é gravado")
    func successWithoutImagesStoresNothing() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com")
        await harness.fetcher.setOutcome(.success(FetchedLinkPreview(title: "Só texto", imageData: Data("lixo".utf8))), for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()

        #expect(
            await harness.deliveries.updates == [
                LinkPreviewUpdate(itemID: request.itemID, pageTitle: "Só texto", state: .ready(fetchedAt: fixedNow))
            ])
        #expect(!FileManager.default.fileExists(atPath: harness.files.directory.path))
    }

    @Test("Falha vira .failed com uma tentativa a mais e campos vazios", arguments: [0, 1, 4])
    func failureBecomesFailedUpdate(previousAttempts: Int) async {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com", attempts: previousAttempts)
        await harness.fetcher.setOutcome(.failure(URLError(.notConnectedToInternet)), for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()

        #expect(
            await harness.deliveries.updates == [
                LinkPreviewUpdate(itemID: request.itemID, state: .failed(at: fixedNow, attempts: previousAttempts + 1))
            ])
    }

    @Test("Contador de tentativas absurdo (de um board.json importado) é limitado e não trava")
    func absurdAttemptCountIsClamped() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com", attempts: Int.max)
        await harness.fetcher.setOutcome(.failure(URLError(.notConnectedToInternet)), for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()

        #expect(
            await harness.deliveries.updates == [
                LinkPreviewUpdate(itemID: request.itemID, state: .failed(at: fixedNow, attempts: 1_001))
            ])
    }

    @Test("Falha ao gravar os arquivos também vira .failed")
    func storeFailureBecomesFailedUpdate() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("MuralQueueBlocker-\(UUID().uuidString)")
        try Data("arquivo".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let harness = Harness(filesDirectory: blocker.appendingPathComponent("Previews", isDirectory: true))
        let request = harness.request("a.example.com", attempts: 1)
        await harness.fetcher.setOutcome(
            .success(FetchedLinkPreview(title: "Título", imageData: try TestImages.png(width: 200, height: 100))), for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()

        #expect(await harness.deliveries.updates == [LinkPreviewUpdate(itemID: request.itemID, state: .failed(at: fixedNow, attempts: 2))])
    }

    @Test("Erro de cancelamento do buscador não gera resultado, e o cartão pode ser enfileirado de novo")
    func fetcherCancellationProducesNoUpdate() async {
        let harness = Harness()
        defer { harness.cleanup() }
        let request = harness.request("a.example.com")
        await harness.fetcher.setOutcome(.failure(CancellationError()), for: request.itemID)
        await harness.fetcher.releaseAll()

        await harness.queue.enqueue([request])
        await harness.settle()
        #expect(await harness.deliveries.batches.isEmpty)

        await harness.fetcher.setOutcome(.success(FetchedLinkPreview(title: "Agora foi")), for: request.itemID)
        await harness.queue.enqueue([request])
        await harness.settle()
        #expect(await harness.deliveries.updates.map(\.pageTitle) == ["Agora foi"])
    }

    // MARK: Lotes

    @Test("Buscas que terminam juntas são entregues num lote só, e uma onda posterior forma outro lote", .timeLimit(.minutes(1)))
    func finishesTogetherAreDeliveredInOneBatch() async {
        // O prazo do lote só acaba quando o teste libera: com a máquina lenta, as três buscas continuam no mesmo lote.
        let sleeper = ManualSleeper()
        let harness = Harness(batchDelay: .seconds(1), sleeper: sleeper)
        defer { harness.cleanup() }
        let wave = (0..<3).map { harness.request("host\($0).example.com", $0) }
        await harness.queue.enqueue(wave)
        await harness.waitForStarts(3)

        await harness.fetcher.releaseAll()
        await waitUntilBatchWaits(harness, sleeper, count: 3)
        await sleeper.releaseAll()
        await harness.settle()

        let batches = await harness.deliveries.batches
        #expect(batches.count == 1)
        #expect(Set(batches.first?.map(\.itemID) ?? []) == Set(wave.map(\.itemID)))

        let later = harness.request("outro.example.com")
        await harness.queue.enqueue([later])
        await waitUntilBatchWaits(harness, sleeper, count: 1)
        await sleeper.releaseAll()
        await harness.settle()
        #expect(await harness.deliveries.batches.count == 2)
        #expect(await harness.deliveries.batches.last?.map(\.itemID) == [later.itemID])
    }

    @Test("O lote só sai depois do prazo contado a partir do primeiro resultado")
    func batchWaitsForTheDelay() async {
        let harness = Harness(batchDelay: .milliseconds(300))
        defer { harness.cleanup() }
        await harness.queue.enqueue([harness.request("a.example.com")])
        await harness.waitForStarts(1)

        let clock = ContinuousClock()
        let start = clock.now
        await harness.fetcher.releaseAll()
        await harness.settle()

        #expect(clock.now - start >= .milliseconds(280), "entregou cedo demais: \(clock.now - start)")
        #expect(await harness.deliveries.batches.count == 1)
    }

    @Test("Com prazo zero cada resultado é entregue logo, sem esperar o resto")
    func zeroDelayDeliversPromptly() async {
        let harness = Harness(batchDelay: .zero)
        defer { harness.cleanup() }
        let first = harness.request("a.example.com", 1)
        let second = harness.request("b.example.com", 2)
        await harness.queue.enqueue([first, second])
        await harness.waitForStarts(2)

        await harness.fetcher.release(first.itemID)
        await waitUntil("primeiro resultado entregue") { await harness.deliveries.updates.map(\.itemID) == [first.itemID] }
        #expect(await harness.fetcher.finishedCount == 1, "o segundo ainda está parado")

        await harness.fetcher.release(second.itemID)
        await harness.settle()
        #expect(await harness.deliveries.updates.map(\.itemID) == [first.itemID, second.itemID])
    }

    // MARK: Cancelamento e ociosidade

    @Test("cancelAll esvazia a fila, cancela o que está em andamento e nada é entregue depois")
    func cancelAllStopsEverything() async {
        let harness = Harness(maxConcurrent: 2, batchDelay: .milliseconds(100))
        defer { harness.cleanup() }
        await harness.queue.enqueue((0..<6).map { harness.request("host\($0).example.com", $0) })
        await harness.waitForStarts(2)
        #expect(!(await harness.queue.isIdle))

        await harness.queue.cancelAll()
        #expect(await harness.queue.isIdle)
        await harness.fetcher.releaseAll()
        try? await Task.sleep(for: .milliseconds(400))

        #expect(await harness.deliveries.batches.isEmpty)
        #expect(await harness.fetcher.started.count == 2, "os pedidos que esperavam vaga nunca começam")
        await harness.settle()
    }

    @Test("cancelAll descarta o lote que ainda não foi entregue", .timeLimit(.minutes(1)))
    func cancelAllDiscardsTheUndeliveredBatch() async {
        // O lote fica parado no prazo até o teste liberar: com a máquina lenta, ele não sai antes do cancelamento.
        let sleeper = ManualSleeper()
        let harness = Harness(batchDelay: .seconds(1), sleeper: sleeper)
        defer { harness.cleanup() }
        await harness.fetcher.releaseAll()
        await harness.queue.enqueue([harness.request("a.example.com")])
        await waitUntilBatchWaits(harness, sleeper, count: 1)
        #expect(!(await harness.queue.isIdle), "controle: o resultado espera no lote")

        await harness.queue.cancelAll()
        #expect(await harness.queue.isIdle)
        // Mesmo com o prazo liberado, a entrega cancelada não acontece.
        await sleeper.releaseAll()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await harness.deliveries.batches.isEmpty)
    }

    @Test("Depois de cancelAll a fila volta a funcionar, e o resultado da busca cancelada não aparece")
    func queueWorksAgainAfterCancelAll() async {
        let harness = Harness(batchDelay: .milliseconds(50))
        defer { harness.cleanup() }
        let first = harness.request("a.example.com", 1)
        let second = harness.request("b.example.com", 2)
        await harness.queue.enqueue([first])
        await harness.waitForStarts(1)
        await harness.queue.cancelAll()

        await harness.fetcher.releaseAll()
        await harness.queue.enqueue([second, first])
        await harness.settle()
        try? await Task.sleep(for: .milliseconds(200))

        let delivered = await harness.deliveries.updates.map(\.itemID)
        #expect(
            delivered.sorted { $0.uuidString < $1.uuidString } == [first.itemID, second.itemID].sorted { $0.uuidString < $1.uuidString })
        #expect(await harness.fetcher.started.count == 3, "o primeiro cartão foi buscado de novo")
    }

    @Test("A busca cancelada que termina depois do cancelAll não mexe na contagem da fila, que já foi reaproveitada")
    func staleCompletionDoesNotCorruptTheReusedQueue() async {
        let harness = Harness(maxPerHost: 1)
        defer { harness.cleanup() }
        let stale = harness.request("a.example.com", 1)
        let second = harness.request("a.example.com", 2)
        let third = harness.request("a.example.com", 3)
        await harness.queue.enqueue([stale])
        await harness.waitForStarts(1)
        await harness.queue.cancelAll()

        await harness.queue.enqueue([second, third])
        await harness.waitForStarts(2)
        await harness.fetcher.release(stale.itemID)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await harness.fetcher.started.count == 2, "o terceiro espera: o host já tem a segunda busca em andamento")

        await harness.fetcher.releaseAll()
        await harness.settle()
        let delivered = await harness.deliveries.updates.map(\.itemID)
        #expect(delivered.count == 2 && Set(delivered) == [second.itemID, third.itemID], "a busca cancelada não entrega nada")
    }

    @Test("A fila nasce ociosa, deixa de ser enquanto trabalha e waitUntilIdle volta quando tudo foi entregue")
    func idleState() async {
        let harness = Harness()
        defer { harness.cleanup() }
        #expect(await harness.queue.isIdle)
        await harness.queue.waitUntilIdle()

        await harness.queue.enqueue([harness.request("a.example.com")])
        #expect(!(await harness.queue.isIdle))
        let returned = Flag()
        let waiter = Task {
            await harness.queue.waitUntilIdle()
            await returned.raise()
        }
        await harness.waitForStarts(1)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!(await returned.isRaised), "waitUntilIdle não pode voltar com a busca em andamento")

        await harness.fetcher.releaseAll()
        await waitUntil("waitUntilIdle voltar") { await returned.isRaised }
        await waiter.value

        #expect(await harness.queue.isIdle)
        #expect(await harness.deliveries.batches.count == 1)
        await harness.queue.enqueue([])
        #expect(await harness.queue.isIdle)
    }

    @Test("Os valores padrão e o fechamento final bastam para criar a fila")
    func defaultsAreEnough() async {
        let queue = LinkPreviewQueue(fetcher: GatedFetcher(), files: LinkPreviewFiles(directory: FileManager.default.temporaryDirectory)) {
            _ in
        }
        #expect(await queue.isIdle)
    }
}
