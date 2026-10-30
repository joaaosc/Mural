import AppKit
import MuralKit
import SwiftUI

/// Folha que procura no catálogo do Apple Music a música, o álbum ou a playlist que vai para o texto. Sem acesso ao Apple Music, pede
/// o acesso ou diz onde ligá-lo, como a folha de lembretes.
struct MusicSearchSheet: View {
    /// De onde vêm os resultados.
    let provider: any MusicProviding
    /// Recebe o item escolhido.
    let onPick: (MusicSnapshot) -> Void

    /// Quanto a busca espera a pessoa parar de digitar.
    private static let typingPause: Duration = .milliseconds(300)

    @Environment(\.dismiss) private var dismiss
    @State private var access: MusicAccess
    @State private var query = ""
    @State private var results: [MusicSnapshot] = []
    @State private var selectedKey: String?
    @State private var isSearching = false
    @State private var failed = false
    @FocusState private var fieldHasFocus: Bool

    init(provider: any MusicProviding, onPick: @escaping (MusicSnapshot) -> Void) {
        self.provider = provider
        self.onPick = onPick
        _access = State(initialValue: provider.access)
    }

    private var selected: MusicSnapshot? {
        results.first { $0.dedupeKey == selectedKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch access {
            case .granted: search
            case .notDetermined: notDetermined
            case .denied, .restricted: denied
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 420)
        .task(id: query) { await runSearch() }
    }

    // MARK: Sem acesso

    private var notDetermined: some View {
        message("Para procurar músicas, o Mural precisa de acesso ao Apple Music.", button: "Permitir acesso") {
            Task { access = await provider.requestAccess() }
        }
    }

    private var denied: some View {
        message(
            "O acesso ao Apple Music está desligado. Ative o Mural em Ajustes do Sistema › Privacidade e Segurança › Mídia e Apple Music.",
            button: "Abrir Ajustes do Sistema"
        ) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(button, action: action)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Busca

    private var search: some View {
        VStack(spacing: 0) {
            TextField("Procurar no Apple Music", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldHasFocus)
                .defaultFocus($fieldHasFocus, true)
                .onAppear { fieldHasFocus = true }
                .padding(10)
                .accessibilityIdentifier("music-search-field")
            resultList.frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if failed {
            ContentUnavailableView(
                "Não foi possível procurar", systemImage: "exclamationmark.triangle",
                description: Text("Confira a conexão e tente de novo."))
        } else if results.isEmpty {
            ContentUnavailableView {
                Label(isSearching ? "Procurando…" : "Nenhum resultado", systemImage: "music.note")
            } description: {
                if query.isEmpty { Text("Digite o nome de uma música, de um álbum ou de uma playlist.") }
            }
        } else {
            List(results, id: \.dedupeKey, selection: $selectedKey) { music in
                MusicSearchRow(music: music)
            }
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { _ in
                insert()
            }
            .accessibilityIdentifier("music-search-results")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancelar", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Inserir", action: insert)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
                .accessibilityIdentifier("music-search-insert")
        }
        .padding(12)
    }

    private func insert() {
        guard let selected else { return }
        onPick(selected)
        dismiss()
    }

    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        failed = false
        guard access == .granted, !term.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: Self.typingPause)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await provider.search(term: term)
            guard !Task.isCancelled else { return }
            results = found
            selectedKey = found.first?.dedupeKey
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failed = true
        }
    }
}

/// Uma linha dos resultados: o símbolo do tipo na cor da capa, o título e o artista com o tipo.
private struct MusicSearchRow: View {
    let music: MusicSnapshot

    var body: some View {
        HStack(spacing: 10) {
            MusicArtwork(music: music, maxPixelSize: 96)
                .frame(width: 32, height: 32)
                .clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(music.title).lineLimit(1)
                Text([music.subtitle, music.detailLine].compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Busca de música, claro") {
    MusicSearchSheet(provider: FakeMusic(arguments: []), onPick: { _ in }).preferredColorScheme(.light)
}

#Preview("Busca de música, escuro") {
    MusicSearchSheet(provider: FakeMusic(arguments: []), onPick: { _ in }).preferredColorScheme(.dark)
}
#endif
