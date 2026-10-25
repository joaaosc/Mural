import Testing

@testable import Mural

@Suite("Lifecycle do probe MetricKit")
@MainActor
struct MuralMetricKitProbeTests {
    @Test("reinicia somente depois que os dois iteradores terminam")
    func restartWaitsForBothObservers() async {
        let metrics = ObservationGate()
        let diagnostics = ObservationGate()
        let probe = MuralMetricKitProbe(
            observeMetrics: { report in await metrics.observe(report: report) },
            observeDiagnostics: { report in await diagnostics.observe(report: report) })
        probe.start()
        probe.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        #expect(metrics.starts == 1)
        #expect(diagnostics.starts == 1)

        let stopping = Task { await probe.stop() }
        // O gate só sinaliza o cancelamento após stop() ter iniciado.
        await metrics.waitUntilCancelled()
        #expect(probe.state == .stopping)
        metrics.emit()
        #expect(probe.metricReportCount == 0)
        let concurrentStop = Task { await probe.stop() }
        probe.start()
        #expect(metrics.starts == 1)
        metrics.finish()
        probe.start()
        #expect(diagnostics.starts == 1)
        diagnostics.finish()
        await stopping.value
        await concurrentStop.value
        #expect(probe.state == .stopped)
        await probe.stop()

        probe.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        #expect(metrics.starts == 2)
        #expect(diagnostics.starts == 2)
        metrics.finish()
        diagnostics.finish()
        await probe.stop()
    }

    @Test("conta chegadas sem reter payloads e ignora emissões após stop")
    func countsReports() async {
        let metrics = ObservationGate()
        let diagnostics = ObservationGate()
        let probe = MuralMetricKitProbe(
            observeMetrics: { report in await metrics.observe(report: report) },
            observeDiagnostics: { report in await diagnostics.observe(report: report) })
        await probe.stop()
        #expect(probe.state == .stopped)
        #expect(probe.start())
        #expect(!probe.start())
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        metrics.emit()
        metrics.emit()
        diagnostics.emit()
        #expect(probe.metricReportCount == 2)
        #expect(probe.diagnosticReportCount == 1)
        let stopping = Task { await probe.stop() }
        await metrics.waitUntilCancelled()
        stopping.cancel()
        #expect(!probe.start())
        metrics.finish()
        diagnostics.finish()
        await stopping.value
        metrics.emit()
        diagnostics.emit()
        #expect(probe.state == .stopped)
        #expect(probe.metricReportCount == 2)
        #expect(probe.diagnosticReportCount == 1)
    }

    @Test("callbacks antigos não contam na sessão seguinte")
    func ignoresPreviousSessionCallbacks() async {
        var oldReport: (@MainActor () -> Void)?
        var starts = 0
        let metrics = ObservationGate()
        let diagnostics = ObservationGate()
        let probe = MuralMetricKitProbe(
            observeMetrics: { report in
                starts += 1
                if starts == 1 { oldReport = report }
                await metrics.observe(report: report)
            },
            observeDiagnostics: { report in await diagnostics.observe(report: report) })
        probe.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        metrics.finish()
        diagnostics.finish()
        await probe.stop()
        probe.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        oldReport?()
        #expect(probe.metricReportCount == 0)
        metrics.emit()
        #expect(probe.metricReportCount == 1)
        metrics.finish()
        diagnostics.finish()
        await probe.stop()
    }

    @Test("fim natural de ambas as sequências libera nova sessão")
    func naturalCompletion() async {
        let metrics = ObservationGate()
        let diagnostics = ObservationGate()
        let probe = MuralMetricKitProbe(
            observeMetrics: { report in await metrics.observe(report: report) },
            observeDiagnostics: { report in await diagnostics.observe(report: report) })
        probe.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        metrics.finish()
        await metrics.waitUntilExited()
        #expect(probe.state == .running)
        #expect(!probe.start())
        diagnostics.finish()
        await diagnostics.waitUntilExited()
        #expect(probe.state == .stopped)
        #expect(probe.start())
        await probe.stop()
    }

    @Test("observações não retêm o probe e são canceladas no deinit")
    func releasesProbe() async {
        let metrics = ObservationGate()
        let diagnostics = ObservationGate()
        var probe: MuralMetricKitProbe? = MuralMetricKitProbe(
            observeMetrics: { report in await metrics.observe(report: report) },
            observeDiagnostics: { report in await diagnostics.observe(report: report) })
        weak let weakProbe = probe
        probe?.start()
        await metrics.waitUntilEntered()
        await diagnostics.waitUntilEntered()
        probe = nil
        #expect(weakProbe == nil)
        await metrics.waitUntilCancelled()
        await diagnostics.waitUntilCancelled()
        metrics.finish()
        diagnostics.finish()
    }
}

@MainActor
private final class ObservationGate {
    private(set) var starts = 0
    private var completion: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var cancelled: CheckedContinuation<Void, Never>?
    private var didCancel = false
    private var didExit = false
    private var exited: CheckedContinuation<Void, Never>?

    private var report: (@MainActor () -> Void)?

    func emit() { report?() }

    func observe(report: @escaping @MainActor () -> Void) async {
        self.report = report
        didExit = false
        defer {
            didExit = true
            exited?.resume()
            exited = nil
        }
        starts += 1
        didCancel = false
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion = continuation
                entered?.resume()
                entered = nil
            }
        } onCancel: {
            Task { @MainActor in
                self.didCancel = true
                self.cancelled?.resume()
                self.cancelled = nil
            }
        }
    }

    func waitUntilEntered() async {
        if completion != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func waitUntilCancelled() async {
        if didCancel { return }
        await withCheckedContinuation { cancelled = $0 }
    }

    func waitUntilExited() async {
        if didExit { return }
        await withCheckedContinuation { exited = $0 }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}
