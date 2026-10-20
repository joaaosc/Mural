import Foundation
import Testing
@testable import MuralKit

@Suite("Classificação de conteúdo")
struct ContentClassifierTests {
    @Test("Extensões conhecidas viram o tipo certo", arguments: [
        ("foto.jpeg", ItemKind.image), ("foto.PNG", .image), ("foto.heic", .image),
        ("clip.mov", .video), ("clip.mp4", .video),
        ("doc.pdf", .pdf), ("nota.txt", .text), ("nota.md", .text),
    ])
    func classifiesFiles(name: String, expected: ItemKind) {
        #expect(ContentClassifier.kind(forFileAt: URL(fileURLWithPath: "/tmp/\(name)")) == expected)
    }

    @Test("Extensão desconhecida não é importada")
    func rejectsUnknown() {
        #expect(ContentClassifier.kind(forFileAt: URL(fileURLWithPath: "/tmp/x.xyz123")) == nil)
    }

    @Test("Texto curto vira post-it, longo vira nota, com marcadores vira lista")
    func classifiesText() {
        #expect(ContentClassifier.kind(forText: "Ligar para o marceneiro") == .sticky)
        #expect(ContentClassifier.kind(forText: String(repeating: "palavra ", count: 40)) == .text)
        #expect(ContentClassifier.kind(forText: "Compras\n- pão\n- leite") == .checklist)
        #expect(ContentClassifier.kind(forText: "Só um item\n- pão") == .sticky)
    }

    @Test("Título vem da primeira linha, sem marcadores e encurtado")
    func titles() {
        #expect(ContentClassifier.title(forText: "# Ideias\ncorpo") == "Ideias")
        #expect(ContentClassifier.title(forText: String(repeating: "a", count: 80)).hasSuffix("…"))
        #expect(ContentClassifier.title(forText: "   ") == "Nota")
    }
}
