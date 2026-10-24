import MetricKit
import os

/// Spike isolado para validar a observação cancelável das sequências do MetricKit.
///
/// O app não cria este tipo no lançamento. Nenhum payload é lido, codificado, persistido ou enviado; os logs
/// registram apenas que uma sequência entregou um relatório, sem conteúdo do relatório.
@MainActor
final class MuralMetricKitProbe {
    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "MetricKit")

    /// Um único manager permanece vivo enquanto o probe for usado, como exige o ciclo de observação do MetricKit.
    private let manager = MetricManager()
    private var metricTask: Task<Void, Never>?
    private var diagnosticTask: Task<Void, Never>?

    /// Começa as duas observações uma única vez. Chamadas repetidas não criam tarefas adicionais.
    func start() {
        guard metricTask == nil, diagnosticTask == nil else { return }

        let manager = self.manager
        let log = Self.log
        metricTask = Task { [manager, log] in
            for await _ in manager.metricReports {
                guard !Task.isCancelled else { return }
                log.debug("Metric report observed")
            }
        }

        diagnosticTask = Task { [manager, log] in
            for await _ in manager.diagnosticReports {
                guard !Task.isCancelled else { return }
                log.debug("Diagnostic report observed")
            }
        }
    }

    /// Cancela as duas observações. Chamadas repetidas não têm efeito.
    func stop() {
        metricTask?.cancel()
        diagnosticTask?.cancel()
        metricTask = nil
        diagnosticTask = nil
    }
}
