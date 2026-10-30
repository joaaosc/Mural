import MuralKit
import SwiftUI

/// A janela "Colar no mural": à esquerda a galeria de murais (prévia grande e tira de miniaturas), à direita o "Colar como" com os
/// jeitos de colar o texto do editor.
///
/// O teclado é de um contêiner só: ←/→ (e Home/End) trocam de mural, ↑/↓ trocam o jeito de colar, letras procuram o mural pelo nome,
/// Return cola e Esc fecha. Depois de colar, a janela mostra "Colado em …" por um segundo e fecha; o editor continua aberto com o
/// texto. Fechar nunca pergunta nada.
struct PasteDestinationView: View {
    let model: PasteDestinationModel

    /// Quanto "Colado em …" fica à vista antes de a janela fechar. Nos testes de interface é mais longo, porque a leitura da tela
    /// pelo teste é lenta e perderia a frase.
    static let confirmationPause: Duration = LaunchConfiguration.isUITesting ? .seconds(5) : .seconds(1)

    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var hasFocus: Bool

    var body: some View {
        HStack(spacing: 0) {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Não foi possível ler os murais", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.isLoaded && model.entries.isEmpty {
                ContentUnavailableView(
                    "Nenhum mural ainda", systemImage: "rectangle.on.rectangle",
                    description: Text("Crie um mural para colar o texto nele."))
            } else {
                GalleryPane(
                    entries: model.entries, selection: model.selection, covers: model.covers.images, select: { model.select($0) })
                Divider()
                PasteDestinationSidebar(model: model, requestPaste: { model.requestPaste() }, close: close)
            }
        }
        .frame(width: PasteDestinationWindow.size.width, height: PasteDestinationWindow.size.height)
        .focusable()
        .focused($hasFocus)
        .defaultFocus($hasFocus, true)
        .focusEffectDisabled()
        .onAppear { hasFocus = true }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in step(-1) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in step(1) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in stepKind(-1) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in stepKind(1) }
        .onKeyPress(.home) {
            model.selectFirst()
            return .handled
        }
        .onKeyPress(.end) {
            model.selectLast()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            model.requestPaste()
            return .handled
        }
        .onKeyPress(characters: .alphanumerics, phases: .down) { press in
            guard press.modifiers.subtracting([.shift, .capsLock]).isEmpty else { return .ignored }
            model.type(press.characters)
            return .handled
        }
        .onExitCommand(perform: close)
        .navigationTitle("Colar no mural")
        .task { await model.load() }
        .task(id: model.status) {
            guard case .pasted = model.status else { return }
            try? await Task.sleep(for: Self.confirmationPause)
            guard !Task.isCancelled else { return }
            close()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PasteDestinationWindow.accessibilityIdentifier)
    }

    private func close() {
        dismissWindow(id: PasteDestinationWindow.sceneID)
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        model.move(by: offset)
        return .handled
    }

    private func stepKind(_ offset: Int) -> KeyPress.Result {
        model.moveKind(by: offset)
        return .handled
    }
}

#if DEBUG
private struct PasteDestinationSample: View {
    private static let entries = ["Casa", "Obra", "Compras", "Viagem"].map { name in
        let id = BoardID()
        return BoardLibraryEntry(manifest: BoardManifest(id: id, name: name), route: .saved(id))
    }

    var body: some View {
        HStack(spacing: 0) {
            GalleryPane(entries: Self.entries, selection: 1, covers: [:], select: { _ in })
            Divider()
            PasteKindList(
                suggestion: PasteKindSuggestion(
                    suggested: .text, options: [.sticky, .text, .checklist],
                    unavailable: [.sticky: "Sticker não guarda imagens nem cartões", .checklist: "Lista não guarda imagens nem cartões"]),
                selectedKind: .text, boardName: "Obra", choose: { _ in }
            )
            .padding(16)
            .frame(width: PasteDestinationSidebar.width)
        }
        .frame(width: PasteDestinationWindow.size.width, height: PasteDestinationWindow.size.height)
    }
}

#Preview("Colar no mural, claro") {
    PasteDestinationSample().preferredColorScheme(.light)
}

#Preview("Colar no mural, escuro") {
    PasteDestinationSample().preferredColorScheme(.dark)
}
#endif
