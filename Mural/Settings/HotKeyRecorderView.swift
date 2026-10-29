import AppKit
import Carbon.HIToolbox
import SwiftUI

enum HotKeyCapturePolicy {
    static func shouldHandle(eventWindowIsRecorderWindow: Bool, recorderWindowIsKey: Bool, recorderIsFocused: Bool) -> Bool {
        eventWindowIsRecorderWindow && recorderWindowIsKey && recorderIsFocused
    }
}

/// Grava a combinação de teclas do atalho que abre o painel, e mostra se ele está valendo.
///
/// Só escuta o teclado depois do clique em "Gravar" e só dentro das janelas do Mural. Enquanto grava, o atalho atual fica
/// solto, para apertá-lo de novo gravar a combinação em vez de abrir o painel. Esc cancela.
struct HotKeyRecorderView: View {
    let center: PanelHotKeyCenter

    @State private var isRecording = false
    /// O monitor de teclado do app enquanto grava.
    @State private var monitor: Any?
    @State private var recorderWindow: NSWindow?
    @FocusState private var recorderIsFocused: Bool

    var body: some View {
        Group {
            row
            if let failure = center.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stopRecording)
        .background {
            HotKeyWindowObserver { window in
                if isRecording, recorderWindow !== window { stopRecording() }
                recorderWindow = window
            }
        }
        .onChange(of: recorderIsFocused) { _, focused in
            if isRecording && !focused { stopRecording() }
        }
    }

    private var row: some View {
        LabeledContent("Abrir o painel") {
            HStack {
                Button(recordLabel, action: toggleRecording)
                    .buttonStyle(.bordered)
                    .focused($recorderIsFocused)
                    .help(isRecording ? "Aperte a combinação nova, ou Esc para cancelar" : "Gravar outra combinação")
                    .accessibilityIdentifier("settings-hotkey-record")
                Menu("Mais opções do atalho", systemImage: "ellipsis") {
                    Button("Voltar para ⌘`", action: restoreStandard)
                        .disabled(center.isStandard)
                    Button("Remover atalho", role: .destructive, action: remove)
                        .disabled(center.hotKey == nil)
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("settings-hotkey-more")
            }
        }
    }

    private var recordLabel: String {
        if isRecording { return "Aperte as teclas…" }
        return center.hotKey?.displayString ?? "Gravar atalho"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil, let recorderWindow, recorderWindow.isKeyWindow else { return }
        isRecording = true
        center.setRecording(true)
        recorderIsFocused = true
        let keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: recorderWindow, queue: .main
        ) { _ in
            Task { @MainActor in stopRecording() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard
                HotKeyCapturePolicy.shouldHandle(
                    eventWindowIsRecorderWindow: event.window === recorderWindow,
                    recorderWindowIsKey: recorderWindow.isKeyWindow,
                    recorderIsFocused: recorderIsFocused
                )
            else { return event }
            guard event.keyCode != UInt16(kVK_Escape) else {
                stopRecording()
                return nil
            }
            guard let hotKey = PanelHotKey(event: event) else {
                // Sem ⌘ ou ⌃ não é atalho: o som avisa, e a gravação continua esperando.
                NSSound.beep()
                return nil
            }
            center.update(to: hotKey)
            stopRecording()
            return nil
        }
        windowObserver = keyObserver
    }

    @State private var windowObserver: NSObjectProtocol?

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        isRecording = false
        recorderIsFocused = false
        center.setRecording(false)
    }

    private func restoreStandard() {
        stopRecording()
        center.restoreStandard()
    }

    private func remove() {
        stopRecording()
        center.remove()
    }
}

private struct HotKeyWindowObserver: NSViewRepresentable {
    var onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowTrackingView)?.onWindowChange = onWindowChange
    }

    private final class WindowTrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        private weak var lastWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard lastWindow !== window else { return }
            lastWindow = window
            onWindowChange?(window)
        }
    }
}
