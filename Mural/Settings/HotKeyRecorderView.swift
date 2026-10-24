import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Grava a combinação de teclas do atalho que abre o painel, e mostra se ele está valendo.
///
/// Só escuta o teclado depois do clique em "Gravar" e só dentro das janelas do Mural. Enquanto grava, o atalho atual fica
/// solto, para apertá-lo de novo gravar a combinação em vez de abrir o painel. Esc cancela.
struct HotKeyRecorderView: View {
    let center: PanelHotKeyCenter

    @State private var isRecording = false
    /// O monitor de teclado do app enquanto grava.
    @State private var monitor: Any?

    var body: some View {
        Group {
            row
            if let failure = center.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var row: some View {
        LabeledContent("Abrir o painel") {
            HStack {
                Button(recordLabel, action: toggleRecording)
                    .buttonStyle(.bordered)
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
        guard monitor == nil else { return }
        isRecording = true
        center.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
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
