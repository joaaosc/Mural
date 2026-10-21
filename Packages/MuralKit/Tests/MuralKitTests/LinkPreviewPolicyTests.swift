import Foundation
import Testing

@testable import MuralKit

@Suite("Política de busca das prévias")
struct LinkPreviewPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600
    private let week: TimeInterval = 7 * 24 * 3_600

    @Test("Prévia pendente é buscada sempre")
    func pendingIsFetched() {
        #expect(LinkPreviewPolicy.shouldFetch(.pending, now: now))
        #expect(LinkPreviewPolicy.shouldFetch(.pending, now: .distantFuture))
    }

    @Test("Prévia pronta nunca é buscada de novo, por mais antiga que seja")
    func readyIsNeverFetchedAgain() {
        #expect(!LinkPreviewPolicy.shouldFetch(.ready(fetchedAt: now), now: now))
        #expect(!LinkPreviewPolicy.shouldFetch(.ready(fetchedAt: now), now: now.addingTimeInterval(10 * week)))
        #expect(!LinkPreviewPolicy.shouldFetch(.ready(fetchedAt: .distantPast), now: now))
    }

    @Test(
        "Falha só é tentada de novo depois do intervalo da quantidade de falhas",
        arguments: [
            (1, 3_600.0), (2, 7_200.0), (3, 14_400.0), (4, 28_800.0), (8, 460_800.0), (9, 604_800.0), (30, 604_800.0),
        ])
    func failureWaitsForTheInterval(attempts: Int, delay: TimeInterval) {
        let state = LinkPreviewState.failed(at: now, attempts: attempts)
        #expect(!LinkPreviewPolicy.shouldFetch(state, now: now))
        #expect(!LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(delay / 2)))
        #expect(!LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(delay - 1)))
        #expect(LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(delay)))
        #expect(LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(delay + 1)))
        #expect(LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(delay * 3)))
    }

    @Test("A espera é de 1 hora depois da primeira falha e dobra a cada falha seguinte")
    func retryDelayDoubles() {
        let expected: [TimeInterval] = [1, 2, 4, 8, 16, 32, 64, 128].map { $0 * hour }
        #expect((1...8).map { LinkPreviewPolicy.retryDelay(afterAttempts: $0) } == expected)
    }

    @Test(
        "A espera nunca passa de 7 dias, mesmo com um número absurdo de falhas", arguments: [9, 10, 11, 20, 21, 22, 40, 64, 1_000, Int.max])
    func retryDelayIsCapped(attempts: Int) {
        #expect(LinkPreviewPolicy.retryDelay(afterAttempts: attempts) == week)
    }

    @Test("Zero ou menos falhas contam como uma", arguments: [0, -1, -100, Int.min])
    func nonPositiveAttemptsCountAsOne(attempts: Int) {
        #expect(LinkPreviewPolicy.retryDelay(afterAttempts: attempts) == hour)
    }

    @Test("Com o teto de 7 dias, uma falha antiga demais para dobrar ainda espera 7 dias")
    func cappedFailureWaitsAWeek() {
        let state = LinkPreviewState.failed(at: now, attempts: 50)
        #expect(!LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(week - 1)))
        #expect(LinkPreviewPolicy.shouldFetch(state, now: now.addingTimeInterval(week)))
    }

    @Test("Falha datada no futuro (relógio que voltou) não bloqueia a nova tentativa")
    func failureInTheFutureDoesNotBlock() {
        #expect(LinkPreviewPolicy.shouldFetch(.failed(at: now.addingTimeInterval(1), attempts: 1), now: now))
        #expect(LinkPreviewPolicy.shouldFetch(.failed(at: now.addingTimeInterval(10 * week), attempts: 5), now: now))
    }
}
