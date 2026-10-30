import Foundation
import MuralKit
import Testing
import UniformTypeIdentifiers

@testable import Mural

@MainActor
struct PasteEditorResolverTests {
    private let textEdit = URL(filePath: "/Applications/TextEdit.app")
    private let preview = URL(filePath: "/Applications/Preview.app")
    private let other = URL(filePath: "/Applications/Outro.app")

    private func lookup(
        installed: [String: URL] = [:], defaults: [UTType: URL] = [:], names: [URL: String] = [:]
    ) -> PasteEditorResolver.Lookup {
        PasteEditorResolver.Lookup(
            applicationURL: { installed[$0] },
            defaultApplicationURL: { defaults[$0] },
            displayName: { names[$0] ?? $0.lastPathComponent },
            bundleIdentifier: { url in installed.first { $0.value == url }?.key })
    }

    @Test("O app padrão do tipo, quando está instalado")
    func defaultEditorFound() {
        let lookup = lookup(
            installed: ["com.apple.TextEdit": textEdit, "com.apple.Preview": preview],
            names: [textEdit: "TextEdit", preview: "Pré-Visualização"])

        #expect(
            PasteEditorResolver.editor(for: .text, lookup: lookup)
                == PasteEditorApp(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", url: textEdit))
        #expect(PasteEditorResolver.editor(for: .image, lookup: lookup)?.name == "Pré-Visualização")
        #expect(PasteEditorResolver.editor(for: .pdf, lookup: lookup)?.url == preview)
    }

    @Test("Sem o app padrão, vale o que o sistema abre por padrão para o formato")
    func fallsBackToTheSystemDefault() {
        let lookup = lookup(defaults: [.plainText: other], names: [other: "Outro"])

        #expect(PasteEditorResolver.editor(for: .text, lookup: lookup) == PasteEditorApp(name: "Outro", bundleIdentifier: nil, url: other))
    }

    @Test("O app preferido vem antes do padrão")
    func preferredEditorWins() {
        let lookup = lookup(installed: ["com.apple.TextEdit": textEdit, "com.exemplo.Editor": other], names: [other: "Editor"])

        #expect(PasteEditorResolver.editor(for: .text, preferring: "com.exemplo.Editor", lookup: lookup)?.url == other)
    }

    @Test("Preferido que não está instalado cai no padrão do tipo")
    func missingPreferredFallsBackToTheKindDefault() {
        let lookup = lookup(installed: ["com.apple.TextEdit": textEdit])

        #expect(PasteEditorResolver.editor(for: .text, preferring: "com.exemplo.Ausente", lookup: lookup)?.url == textEdit)
    }

    @Test("Sem nenhum app, não há editor")
    func nothingAvailable() {
        #expect(PasteEditorResolver.editor(for: .text, lookup: lookup()) == nil)
        #expect(PasteEditorResolver.editor(for: .image, preferring: "com.exemplo.Ausente", lookup: lookup()) == nil)
    }

    @Test("O .app do fim do nome é tirado")
    func appSuffixIsStripped() {
        let lookup = lookup(installed: ["com.apple.TextEdit": textEdit], names: [textEdit: "TextEdit.app"])

        #expect(PasteEditorResolver.editor(for: .text, lookup: lookup)?.name == "TextEdit")
    }
}
