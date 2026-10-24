import Foundation
import MetricKit
import os

/// Observação local e explícita. Não é criada no lançamento nem acessa conteúdo dos relatórios.
@MainActor
final class MuralMetricKitProbe {
    enum State: Equatable {
        case stopped
        case running
        case stopping
    }

    typealias Observation = @MainActor (@escaping @MainActor () -> Void) async -> Void

    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "MetricKit")
    private let observeMetrics: Observation
    private let observeDiagnostics: Observation
    private var metricTask: Task<Void, Never>?
    private var diagnosticTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var sessionID: UUID?

    private(set) var state = State.stopped
    /// Contadores em memória, cumulativos durante a vida do probe; nenhum payload é retido.
    private(set) var metricReportCount = 0
    private(set) var diagnosticReportCount = 0

    convenience init() {
        // As duas observações retêm o mesmo manager, inclusive entre reinícios.
        let manager = MetricManager()
        self.init(
            observeMetrics: { report in
                for await _ in manager.metricReports {
                    guard !Task.isCancelled else { return }
                    report()
                }
            },
            observeDiagnostics: { report in
                for await _ in manager.diagnosticReports {
                    guard !Task.isCancelled else { return }
                    report()
                }
            })
    }

    /// Observações injetáveis permitem validar o lifecycle sem esperar relatórios diários.
    init(observeMetrics: @escaping Observation, observeDiagnostics: @escaping Observation) {
        self.observeMetrics = observeMetrics
        self.observeDiagnostics = observeDiagnostics
    }

    deinit {
        metricTask?.cancel()
        diagnosticTask?.cancel()
    }

    /// Retorna false se já há uma sessão ativa ou ainda drenando.
    @discardableResult
    func start() -> Bool {
        guard state == .stopped else { return false }
        state = .running
        let sessionID = UUID()
        self.sessionID = sessionID
        metricTask = Task { [weak self, observeMetrics] in
            guard !Task.isCancelled else { return }
            await observeMetrics { [weak self] in
                guard !Task.isCancelled, let self, self.state == .running, self.sessionID == sessionID else {
                    return
                }
                if self.metricReportCount < Int.max { self.metricReportCount += 1 }
                Self.log.debug("Metric report observed")
            }
            self?.observationFinished(metrics: true)
        }
        diagnosticTask = Task { [weak self, observeDiagnostics] in
            guard !Task.isCancelled else { return }
            await observeDiagnostics { [weak self] in
                guard !Task.isCancelled, let self, self.state == .running, self.sessionID == sessionID else {
                    return
                }
                if self.diagnosticReportCount < Int.max { self.diagnosticReportCount += 1 }
                Self.log.debug("Diagnostic report observed")
            }
            self?.observationFinished(metrics: false)
        }
        return true
    }

    /// Cancelar quem chama stop() não cancela a drenagem compartilhada.
    /// Uma sequência não cooperativa mantém state == .stopping e impede sobreposição.
    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard state == .running else { return }
        state = .stopping
        let metrics = metricTask
        let diagnostics = diagnosticTask
        metrics?.cancel()
        diagnostics?.cancel()
        let drain = Task { [weak self] in
            await metrics?.value
            await diagnostics?.value
            self?.finishStopping()
        }
        stopTask = drain
        await drain.value
    }

    private func observationFinished(metrics: Bool) {
        if metrics {
            metricTask = nil
        } else {
            diagnosticTask = nil
        }
        // Uma sequência pode terminar naturalmente. A outra continua observada;
        // somente o encerramento de ambas permite outra sessão.
        if state == .running, metricTask == nil, diagnosticTask == nil {
            sessionID = nil
            state = .stopped
        }
    }

    private func finishStopping() {
        metricTask = nil
        diagnosticTask = nil
        stopTask = nil
        sessionID = nil
        state = .stopped
    }
}
