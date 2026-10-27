import Foundation
import Testing

@testable import MuralKit

@Suite("Plano das cópias no iCloud Drive")
struct DriveMirrorPlanTests {
    private typealias Action = DriveMirrorPlan.Action

    private let a = BoardID(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
    private let b = BoardID(UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!)
    private let c = BoardID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!)
    private let stranger = BoardID(UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!)

    /// Mural da própria pessoa no iCloud dela.
    private let owned = BoardCloudInfo(database: .private, zoneName: "Mural-1", zoneOwnerName: "_dono", permission: .owner)
    /// Mural recebido de outra pessoa.
    private let received = BoardCloudInfo(
        database: .shared, zoneName: "Mural-2", zoneOwnerName: "_ana", ownerDisplayName: "Ana", permission: .readWrite)

    private func board(_ id: BoardID, _ name: String, cloud: BoardCloudInfo? = nil) -> BoardManifest {
        BoardManifest(id: id, name: name, cloud: cloud)
    }

    private func plan(
        _ boards: [BoardManifest], copies: [String: BoardID?] = [:], writes: Set<BoardID> = [], trash: Set<BoardID> = [],
        awaiting: Set<BoardID> = []
    ) -> [Action] {
        DriveMirrorPlan.make(
            boards: boards, copies: copies, pendingWrites: writes, pendingTrash: trash, awaitingFirstFetch: awaiting
        ).actions
    }

    /// Aplica as ações à pasta, como o app faria, e devolve o que há nela depois.
    private func apply(_ actions: [Action], to folder: [String: BoardID?]) -> [String: BoardID?] {
        var result = folder
        for action in actions {
            switch action {
            case .trash(_, let fileName):
                result.removeValue(forKey: fileName)
            case .move(_, let from, let to):
                if let moved = result.removeValue(forKey: from) { result[to] = moved }
            case .write(let id, let fileName):
                result.updateValue(id, forKey: fileName)
            }
        }
        return result
    }

    // MARK: Quem tem cópia, e quando ela é gravada

    @Test("Mural só deste Mac sem cópia: grava")
    func localBoardWithoutCopyIsWritten() {
        #expect(plan([board(a, "Ideias")]) == [.write(a, fileName: "Ideias.mural")])
    }

    @Test("Mural do iCloud dela com a cópia no nome certo: nada, a não ser que este Mac o tenha mudado")
    func privateBoardIsWrittenOnlyWhenPending() {
        let boards = [board(a, "Ideias", cloud: owned)]
        let copies: [String: BoardID?] = ["Ideias.mural": a]

        #expect(plan(boards, copies: copies).isEmpty)
        #expect(plan(boards, copies: copies, writes: [a]) == [.write(a, fileName: "Ideias.mural")])
    }

    @Test("Mural renomeado: a cópia muda de nome e, se este Mac o mudou, é regravada no nome novo")
    func renamedBoardMovesItsCopy() {
        let boards = [board(a, "Viagens")]
        let copies: [String: BoardID?] = ["Ideias.mural": a]

        #expect(plan(boards, copies: copies) == [.move(a, from: "Ideias.mural", to: "Viagens.mural")])
        #expect(
            plan(boards, copies: copies, writes: [a]) == [
                .move(a, from: "Ideias.mural", to: "Viagens.mural"), .write(a, fileName: "Viagens.mural"),
            ])
    }

    @Test("Mural recebido de outra pessoa nunca tem cópia: nem gravação nem troca de nome")
    func receivedBoardGetsNoCopy() {
        let shared = board(b, "Compartilhado", cloud: received)

        #expect(plan([shared], writes: [b]).isEmpty)
        #expect(plan([shared], copies: ["Antigo.mural": b], writes: [b]).isEmpty)
    }

    @Test("Mural que ainda espera a primeira busca no iCloud não tem cópia")
    func awaitingBoardGetsNoCopy() {
        let adopted = board(c, "Adotado", cloud: owned)

        #expect(plan([adopted], awaiting: [c]).isEmpty)
        #expect(plan([adopted], copies: ["Antigo.mural": c], writes: [c], awaiting: [c]).isEmpty)
        // Depois da primeira busca, volta a valer a regra comum.
        #expect(plan([adopted]) == [.write(c, fileName: "Adotado.mural")])
    }

    // MARK: Lixo

    @Test("Mural excluído neste Mac: todas as cópias dele vão ao Lixo, e só as dele")
    func trashesEveryCopyOfADeletedBoard() {
        let copies: [String: BoardID?] = ["Beta.mural": a, "Alpha.mural": a, "Outro.mural": b, "Quebrado.mural": nil]

        #expect(plan([], copies: copies, trash: [a]) == [.trash(a, fileName: "Alpha.mural"), .trash(a, fileName: "Beta.mural")])
    }

    @Test("Mural fora da biblioteca sem a marca de exclusão: nada (outro Mac, ou saiu pelo iCloud)")
    func keepsCopiesOfBoardsThatLeftOtherWays() {
        #expect(plan([], copies: ["Alpha.mural": a, "Quebrado.mural": nil]).isEmpty)
    }

    @Test("Marca de exclusão de mural que ainda está na biblioteca: nada")
    func ignoresTheTrashMarkOfABoardStillInTheLibrary() {
        #expect(plan([board(a, "Alpha")], copies: ["Alpha.mural": a], trash: [a]).isEmpty)
    }

    // MARK: Nomes

    @Test("Dois murais com o mesmo nome: o segundo, pela ordem, ganha o sufixo, sempre o mesmo")
    func duplicateNamesGetASuffixOnTheSecond() {
        let first = board(a, "Ideias")
        let second = board(b, "Ideias")

        let result = plan([first, second])
        #expect(result.count == 2)
        #expect(result.contains(.write(a, fileName: "Ideias.mural")))
        #expect(result.contains(.write(b, fileName: "Ideias (BBBBBBBB).mural")))
        // A ordem em que a biblioteca entrega os murais não muda nada.
        #expect(plan([second, first]) == result)
        // Com as cópias já na pasta, o plano seguinte é vazio.
        #expect(plan([first, second], copies: ["Ideias.mural": a, "Ideias (BBBBBBBB).mural": b]).isEmpty)
    }

    @Test("Nome ocupado por pacote de outro mural ou ilegível: sufixo; se até esse estiver ocupado, o id inteiro")
    func occupiedNamesGetASuffix() {
        let boards = [board(a, "Ideias")]
        let suffixed = Action.write(a, fileName: "Ideias (AAAAAAAA).mural")

        #expect(plan(boards, copies: ["Ideias.mural": stranger]) == [suffixed])
        #expect(plan(boards, copies: ["Ideias.mural": nil]) == [suffixed])
        // Maiúsculas e minúsculas não distinguem nomes (o volume padrão do Mac).
        #expect(plan(boards, copies: ["ideias.MURAL": stranger]) == [suffixed])
        // Pacote de um mural recebido, que nunca tem cópia, também ocupa o nome.
        #expect(plan([board(a, "Ideias"), board(b, "Ideias", cloud: received)], copies: ["Ideias.mural": b]) == [suffixed])

        let occupiedTwice: [String: BoardID?] = ["Ideias.mural": stranger, "Ideias (AAAAAAAA).mural": nil]
        #expect(
            plan(boards, copies: occupiedTwice) == [.write(a, fileName: "Ideias (AAAAAAAA-0000-0000-0000-000000000001).mural")])
    }

    @Test("Duas cópias do mesmo mural: vale a do nome desejado; a outra fica como está")
    func twoCopiesOfTheSameBoard() {
        let boards = [board(a, "Beta")]

        #expect(plan(boards, copies: ["Alpha.mural": a, "Beta.mural": a]).isEmpty)
        #expect(plan(boards, copies: ["Alpha.mural": a, "Beta.mural": a], writes: [a]) == [.write(a, fileName: "Beta.mural")])
        // Nenhuma no nome desejado: a primeira, em ordem de nome, é a que muda de nome.
        #expect(plan(boards, copies: ["Alpha.mural": a, "Alfa.mural": a]) == [.move(a, from: "Alfa.mural", to: "Beta.mural")])
    }

    // MARK: Ordem das ações

    @Test("Ordem: primeiro o Lixo, depois as trocas de nome, por fim as gravações, cada grupo pelo nome do arquivo")
    func actionsAreOrderedTrashMoveWrite() {
        let boards = [board(a, "Zebra"), board(b, "Viagens")]
        let copies: [String: BoardID?] = ["Ideias.mural": b, "Antigo.mural": c]

        #expect(
            plan(boards, copies: copies, writes: [b], trash: [c]) == [
                .trash(c, fileName: "Antigo.mural"),
                .move(b, from: "Ideias.mural", to: "Viagens.mural"),
                .write(b, fileName: "Viagens.mural"),
                .write(a, fileName: "Zebra.mural"),
            ])
    }

    @Test("Troca de nomes entre dois murais, sem nome livre: nenhuma troca sobrescreve uma cópia")
    func swappedNamesNeverOverwrite() {
        let boards = [board(a, "Alpha"), board(b, "Beta")]
        let copies: [String: BoardID?] = ["Beta.mural": a, "Alpha.mural": b]

        let result = plan(boards, copies: copies, writes: [a, b])

        #expect(
            result == [
                .move(b, from: "Alpha.mural", to: "Beta (BBBBBBBB).mural"),
                .move(a, from: "Beta.mural", to: "Alpha (AAAAAAAA).mural"),
                .write(a, fileName: "Alpha (AAAAAAAA).mural"),
                .write(b, fileName: "Beta (BBBBBBBB).mural"),
            ])
        let occupied = Set(copies.keys.map { $0.lowercased() })
        for case .move(_, _, let destination) in result {
            #expect(!occupied.contains(destination.lowercased()), "\(destination) já está ocupado")
        }
    }

    @Test("Aplicadas as ações, o plano seguinte converge: nada mais a fazer em poucas rodadas")
    func planConverges() {
        let boards = [board(a, "Alpha"), board(b, "Beta"), board(c, "Beta")]
        var folder: [String: BoardID?] = ["Beta.mural": a, "Alpha.mural": b, "Velho.mural": stranger, "Quebrado.mural": nil]
        var pending: Set<BoardID> = [a, b, c]

        for _ in 0..<2 {
            folder = apply(plan(boards, copies: folder, writes: pending, trash: [stranger]), to: folder)
            pending = []
        }

        #expect(folder == ["Alpha.mural": a, "Beta.mural": b, "Beta (CCCCCCCC).mural": c, "Quebrado.mural": nil])
        #expect(plan(boards, copies: folder, trash: [stranger]).isEmpty)
    }

    // MARK: Nome do pacote

    @Test(
        "fileName(for:) troca barra e dois-pontos, tira o ponto do começo, os controles e os espaços das pontas, e acrescenta .mural",
        arguments: [
            ("Ideias", "Ideias.mural"),
            ("Viagem 2026/27", "Viagem 2026-27.mural"),
            ("Reunião: pauta", "Reunião- pauta.mural"),
            (".oculto", "oculto.mural"),
            ("..  .oculto", "oculto.mural"),
            ("...", "Mural.mural"),
            ("", "Mural.mural"),
            ("   \n\t ", "Mural.mural"),
            ("  Plano de ação \n", "Plano de ação.mural"),
            ("A\u{7}B\u{0}C\tD", "ABCD.mural"),
        ])
    func fileNames(name: String, expected: String) {
        #expect(DriveMirrorPlan.fileName(for: name) == expected)
    }

    @Test("fileName(for:) corta em 120 caracteres e em 200 bytes, sem partir uma letra acentuada")
    func longNamesAreCutByCharacterAndBytes() {
        // Letras de 1 byte: o corte é o de 120 caracteres.
        #expect(DriveMirrorPlan.fileName(for: String(repeating: "a", count: 300)) == String(repeating: "a", count: 120) + ".mural")

        // "é" tem 2 bytes: cabem 100 letras.
        let precomposed = DriveMirrorPlan.fileName(for: String(repeating: "é", count: 200))
        #expect(precomposed == String(repeating: "é", count: 100) + ".mural")

        // "e" + acento combinado é uma letra só, de 3 bytes: cabem 66, e o corte não deixa um acento solto.
        let decomposed = DriveMirrorPlan.fileName(for: String(repeating: "e\u{301}", count: 200))
        #expect(decomposed.count == 66 + 6)
        #expect(decomposed.hasSuffix("e\u{301}.mural"))

        // Escrita de 3 bytes por letra: mesmo com o sufixo do id inteiro, o nome cabe nos 255 bytes do volume.
        let wide = DriveMirrorPlan.fileName(for: String(repeating: "漢", count: 150))
        let base = wide.dropLast(".mural".count)
        #expect(base.utf8.count <= 200)
        #expect("\(base) (\(UUID().uuidString)).mural".utf8.count <= 255)
    }
}
