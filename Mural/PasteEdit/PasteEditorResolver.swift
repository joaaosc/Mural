import AppKit
import MuralKit
import UniformTypeIdentifiers

/// O app que abre uma cópia de edição, como a pessoa o vê.
struct PasteEditorApp: Equatable, Sendable {
    /// O nome que aparece na tela, sem o ".app" ("TextEdit", "Pré-Visualização").
    let name: String
    let bundleIdentifier: String?
    let url: URL
}

/// Decide qual app abre cada tipo de cópia de edição, sem abrir nada.
@MainActor
enum PasteEditorResolver {
    /// As perguntas ao sistema, como funções, para os testes responderem sem depender dos apps instalados.
    struct Lookup {
        /// O app com esse identificador, se estiver instalado.
        var applicationURL: (String) -> URL?
        /// O app que o sistema abre por padrão para esse tipo de arquivo.
        var defaultApplicationURL: (UTType) -> URL?
        /// O nome do app como o Finder o mostra.
        var displayName: (URL) -> String
        var bundleIdentifier: (URL) -> String?

        /// As respostas do sistema de verdade.
        static var system: Lookup {
            Lookup(
                applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
                defaultApplicationURL: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
                displayName: { FileManager.default.displayName(atPath: $0.path) },
                bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier })
        }
    }

    /// O app que edita o tipo: o preferido, se estiver instalado; depois o padrão do tipo (``PasteEditKind/defaultEditorBundleIdentifier``);
    /// depois o que o sistema abre por padrão para o formato do arquivo.
    /// - Returns: `nil` quando nenhum existe; sem editor, a opção de editar não aparece.
    static func editor(
        for kind: PasteEditKind, preferring bundleIdentifier: String? = nil, lookup: Lookup = .system
    ) -> PasteEditorApp? {
        let candidates = [bundleIdentifier, kind.defaultEditorBundleIdentifier].compactMap { $0 }
        let url =
            candidates.lazy.compactMap { lookup.applicationURL($0) }.first
            ?? lookup.defaultApplicationURL(kind.contentType)
        guard let url else { return nil }
        var name = lookup.displayName(url)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return PasteEditorApp(name: name, bundleIdentifier: lookup.bundleIdentifier(url), url: url)
    }
}
