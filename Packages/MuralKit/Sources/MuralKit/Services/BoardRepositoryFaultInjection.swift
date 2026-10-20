import Foundation

public enum BoardRepositoryFaultPoint: String, Codable, Equatable, Hashable, Sendable {
    case beforeSwap
    case afterSwap
}

public actor BoardRepositoryFaultGate {
    private var released = false
    private var reached = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation { continuation in
            reachWaiters.append(continuation)
        }
    }

    func waitForRelease() async {
        reached = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    public func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

/// Falhas determinísticas para exercitar rollback sem depender de permissões do sistema.
public struct BoardRepositoryFaultInjection: Sendable {
    public var points: Set<BoardRepositoryFaultPoint>
    public var gate: BoardRepositoryFaultGate?

    public init(points: Set<BoardRepositoryFaultPoint> = [], gate: BoardRepositoryFaultGate? = nil) {
        self.points = points
        self.gate = gate
    }

    public static let none = BoardRepositoryFaultInjection()

    mutating func consume(_ point: BoardRepositoryFaultPoint) -> Bool {
        points.remove(point) != nil
    }
}
