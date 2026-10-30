import Foundation
import Testing

@testable import MuralKit

@Suite("Nome do mural")
struct BoardNameTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralBoardName-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(
        "Acentos, emoji, traço e dois-pontos de largura total são aceitos",
        arguments: ["Viagem à Bahia", "Ideias 💡", "Q1 - 2026", "Hora：10", ""])
    func acceptsOrdinaryNames(_ name: String) {
        #expect(BoardName.issue(in: name) == nil)
    }

    @Test("Dois-pontos e barra são recusados, com o primeiro que aparece")
    func rejectsColonAndSlash() {
        #expect(BoardName.issue(in: "Reunião: pauta") == .forbiddenCharacter(":"))
        #expect(BoardName.issue(in: "Entrada/Saída") == .forbiddenCharacter("/"))
        #expect(BoardName.issue(in: "a/b:c") == .forbiddenCharacter("/"))
        // A barra seguida de acento combinante continua sendo uma barra no disco.
        #expect(BoardName.issue(in: "a/\u{301}b") == .forbiddenCharacter("/"))
    }

    @Test("Quebra de linha, tabulação e nulo são recusados", arguments: ["linha\num", "com\ttab", "nulo\u{0}"])
    func rejectsControlCharacters(_ name: String) {
        #expect(BoardName.issue(in: name) == .controlCharacter)
    }

    @Test("A frase do problema cita o caractere")
    func messageNamesCharacter() {
        #expect(BoardName.Issue.forbiddenCharacter(":").message.contains("“:”"))
    }

    @Test("Limpar troca dois-pontos e barra por traço, tira controles e espaços das pontas")
    func sanitizes() {
        #expect(BoardName.sanitized("Reunião: 10/11") == "Reunião- 10-11")
        #expect(BoardName.sanitized("  linha\num  ") == "linhaum")
        #expect(BoardName.sanitized("\n\t") == BoardName.untitled)
        #expect(BoardName.sanitized("Viagem") == "Viagem")
    }

    @Test("Criar com nome proibido falha sem criar nada")
    func createRejectsForbiddenName() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        await #expect(throws: BoardLibraryError.invalidName(.forbiddenCharacter(":"))) {
            _ = try await library.createNamedBoard("Reunião: pauta")
        }
        #expect(try await library.listSaved().isEmpty)
    }

    @Test("Renomear com nome proibido falha e mantém o nome")
    func renameRejectsForbiddenName() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Antes")
        await #expect(throws: BoardLibraryError.invalidName(.forbiddenCharacter("/"))) {
            _ = try await library.rename(route, to: "Entrada/Saída")
        }
        #expect(try await library.open(route)?.manifest.name == "Antes")
    }

    @Test("Pacote importado com nome proibido entra com o nome limpo")
    func importSanitizesName() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("externo.mural", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("Items", isDirectory: true), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        try encoder.encode(BoardManifest(id: BoardID(), name: "Reunião: 10/11")).write(to: package.appendingPathComponent("manifest.json"))
        try encoder.encode(Board()).write(to: package.appendingPathComponent("board.json"))
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.importPackage(from: package)
        #expect(try await library.open(route)?.manifest.name == "Reunião- 10-11")
    }
}
