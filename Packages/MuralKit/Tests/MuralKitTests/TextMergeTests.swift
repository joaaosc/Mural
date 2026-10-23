import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Um trecho da base trocado por outro: as linhas de `range` saem e as de `lines` entram no lugar (`range` vazio é uma inserção).
private struct LineEdit: Equatable {
    var range: Range<Int>
    var lines: [String]
}

private let sweepBase = (0..<5).map { "linha \($0)" }

/// O texto com os trechos aplicados sobre a base, na ordem do primeiro; trechos iguais valem uma vez.
private func apply(_ edits: [LineEdit], to base: [String]) -> String {
    var unique: [LineEdit] = []
    for edit in edits where !unique.contains(edit) { unique.append(edit) }
    var result: [String] = []
    var cursor = 0
    for edit in unique.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        result += base[cursor..<edit.range.lowerBound]
        result += edit.lines
        cursor = edit.range.upperBound
    }
    result += base[cursor...]
    return result.joined(separator: "\n")
}

/// Toda edição de uma linha só que um lado pode fazer na base da varredura: trocar, apagar ou inserir antes de cada linha e no fim.
/// `tag` deixa o texto novo de um lado diferente do outro.
private func singleEdits(_ tag: String) -> [LineEdit] {
    var edits: [LineEdit] = []
    for index in sweepBase.indices {
        edits.append(LineEdit(range: index..<(index + 1), lines: ["\(tag) \(index)"]))
        edits.append(LineEdit(range: index..<(index + 1), lines: []))
    }
    for index in 0...sweepBase.count {
        edits.append(LineEdit(range: index..<index, lines: ["\(tag) novo \(index)"]))
    }
    return edits
}

// MARK: Testes

@Suite("Junção de texto por linha")
struct TextMergeTests {
    private let base = "Primeiro parágrafo.\n\nSegundo parágrafo.\n\nTerceiro parágrafo."

    // MARK: Atalhos

    @Test("Lados iguais, ou só um deles mudado: vale o que mudou, sem comparar linhas")
    func shortcuts() {
        #expect(TextMerge.merge(base: "a\nb", local: "x\ny", remote: "x\ny") == "x\ny")
        #expect(TextMerge.merge(base: "a\nb", local: "a\nb", remote: "a\nB") == "a\nB")
        #expect(TextMerge.merge(base: "a\nb", local: "A\nb", remote: "a\nb") == "A\nb")
        #expect(TextMerge.merge(base: "a\nb", local: "a\nb", remote: "a\nb") == "a\nb")
    }

    // MARK: Trechos que não colidem

    @Test("Parágrafos diferentes editados pelos dois lados: as duas edições entram")
    func differentParagraphsBothEnter() {
        let local = "Primeiro parágrafo, revisado.\n\nSegundo parágrafo.\n\nTerceiro parágrafo."
        let remote = "Primeiro parágrafo.\n\nSegundo parágrafo.\n\nTerceiro parágrafo, com mais uma frase."
        let expected = "Primeiro parágrafo, revisado.\n\nSegundo parágrafo.\n\nTerceiro parágrafo, com mais uma frase."
        #expect(TextMerge.merge(base: base, local: local, remote: remote) == expected)
        // Sem colisão, trocar os lados dá o mesmo texto.
        #expect(TextMerge.merge(base: base, local: remote, remote: local) == expected)
    }

    @Test("Um lado apaga uma linha e o outro edita uma linha distante: os dois entram")
    func deletionAndDistantEdit() {
        let base = "a\nb\nc\nd\ne"
        #expect(TextMerge.merge(base: base, local: "b\nc\nd\ne", remote: "a\nb\nc\nd\nE") == "b\nc\nd\nE")
        #expect(TextMerge.merge(base: base, local: "a\nb\nc\nd\nE", remote: "b\nc\nd\ne") == "b\nc\nd\nE")
    }

    @Test("Linhas novas em pontos diferentes entram nos dois; no mesmo ponto, colidem")
    func insertionsAtDifferentPoints() {
        let base = "a\nb\nc\nd"
        #expect(TextMerge.merge(base: base, local: "início\na\nb\nc\nd", remote: "a\nb\nc\nd\nfim") == "início\na\nb\nc\nd\nfim")
        // Com uma linha entre os dois pontos, cada inserção tem o seu lugar.
        #expect(TextMerge.merge(base: base, local: "a\nb\nlocal\nc\nd", remote: "a\nb\nc\nremoto\nd") == "a\nb\nlocal\nc\nremoto\nd")
        #expect(TextMerge.merge(base: base, local: "a\nb\nlocal\nc\nd", remote: "a\nb\nremoto\nc\nd") == nil)
    }

    @Test("Linhas em branco e o fim de linha do final do texto voltam como estavam")
    func blankLinesAndTrailingNewlineArePreserved() {
        let base = "a\n\nb\n"
        #expect(TextMerge.merge(base: base, local: "A\n\nb\n", remote: "a\n\nB\n") == "A\n\nB\n")
        #expect(TextMerge.merge(base: "a\n\nb", local: "a\n\nb\n", remote: "A\n\nb") == "A\n\nb\n")
    }

    // MARK: Mesma edição

    @Test("A mesma edição nos dois lados entra uma vez só")
    func identicalEditEntersOnce() {
        let base = "a\nb\nc\nd\ne"
        // Os dois trocam b por B; um ainda acrescenta f no fim e o outro troca d por D.
        #expect(TextMerge.merge(base: base, local: "a\nB\nc\nd\ne\nf", remote: "a\nB\nc\nD\ne") == "a\nB\nc\nD\ne\nf")
        // A mesma linha apagada nos dois lados, e uma edição só de um.
        #expect(TextMerge.merge(base: base, local: "a\nc\nd\nE", remote: "a\nc\nd\ne") == "a\nc\nd\nE")
        // A mesma linha nova no fim nos dois lados.
        #expect(TextMerge.merge(base: "a\nb", local: "x\nb\nc", remote: "a\nb\nc") == "x\nb\nc")
    }

    // MARK: Colisões

    @Test("A mesma linha editada de jeitos diferentes colide")
    func sameLineEditedDifferentlyCollides() {
        let local = "Primeiro parágrafo.\n\nSegundo parágrafo, aqui.\n\nTerceiro parágrafo."
        let remote = "Primeiro parágrafo.\n\nSegundo parágrafo, lá.\n\nTerceiro parágrafo."
        #expect(TextMerge.merge(base: base, local: local, remote: remote) == nil)
    }

    @Test("Linhas vizinhas editadas por lados diferentes colidem; com uma linha no meio, não")
    func neighbouringLinesCollide() {
        let base = "a\nb\nc\nd"
        #expect(TextMerge.merge(base: base, local: "a\nB\nc\nd", remote: "a\nb\nC\nd") == nil)
        #expect(TextMerge.merge(base: base, local: "A\nb\nc\nd", remote: "a\nb\nC\nd") == "A\nb\nC\nd")
    }

    @Test("Linhas novas no fim do texto, diferentes nos dois lados, colidem")
    func appendsAtTheEndCollide() {
        #expect(TextMerge.merge(base: "a\nb", local: "a\nb\nc", remote: "a\nb\nd") == nil)
        // Uma linha nova encostada numa linha editada também colide.
        #expect(TextMerge.merge(base: "a\nb", local: "a\nb\nc", remote: "a\nB") == nil)
    }

    @Test("Trechos apagados que se sobrepõem, sem serem iguais, colidem")
    func overlappingDeletionsCollide() {
        let base = "a\nb\nc\nd"
        #expect(TextMerge.merge(base: base, local: "a\nd", remote: "a\nb") == nil)
    }

    // MARK: Texto vazio

    @Test("Texto vazio: o vazio é uma base como outra qualquer")
    func emptyText() {
        #expect(TextMerge.merge(base: "", local: "", remote: "") == "")
        #expect(TextMerge.merge(base: "", local: "Oi", remote: "") == "Oi")
        #expect(TextMerge.merge(base: "", local: "", remote: "Oi") == "Oi")
        #expect(TextMerge.merge(base: "Oi", local: "", remote: "") == "")
        #expect(TextMerge.merge(base: "", local: "Oi", remote: "Oi") == "Oi")
        // Escrito do zero nos dois lados com textos diferentes é o mesmo lugar.
        #expect(TextMerge.merge(base: "", local: "Oi", remote: "Olá") == nil)
        // Um lado esvazia o texto e o outro mexe nele.
        #expect(TextMerge.merge(base: "Oi", local: "", remote: "Oi\nTchau") == nil)
        #expect(TextMerge.merge(base: "a\nb\nc", local: "", remote: "a\nb\nC") == nil)
    }

    // MARK: Nota longa

    @Test("Nota longa com poucas edições de cada lado: junta sem custo que a torne inviável")
    func longNoteWithFewEdits() {
        let lines = (0..<3_000).map { "Linha \($0) da nota longa." }
        var local = lines
        var remote = lines
        for index in 0..<20 { local[index] = "Linha \(index) revista aqui." }
        for index in 2_980..<3_000 { remote[index] = "Linha \(index) revista lá." }
        var expected = lines
        for index in 0..<20 { expected[index] = local[index] }
        for index in 2_980..<3_000 { expected[index] = remote[index] }

        let merged = TextMerge.merge(
            base: lines.joined(separator: "\n"), local: local.joined(separator: "\n"), remote: remote.joined(separator: "\n"))
        #expect(merged == expected.joined(separator: "\n"))
    }

    // MARK: Varredura

    @Test("Uma edição de cada lado (trocar, apagar ou inserir uma linha) colide exatamente quando os trechos se tocam")
    func singleEditSweep() {
        let baseText = sweepBase.joined(separator: "\n")
        var merged = 0
        var collided = 0
        for local in singleEdits("L") {
            for remote in singleEdits("R") {
                let localText = apply([local], to: sweepBase)
                let remoteText = apply([remote], to: sweepBase)
                let touching = local.range.lowerBound <= remote.range.upperBound && remote.range.lowerBound <= local.range.upperBound
                let expected = touching && local != remote ? nil : apply([local, remote], to: sweepBase)
                let result = TextMerge.merge(base: baseText, local: localText, remote: remoteText)
                #expect(result == expected, "local \(local) × remoto \(remote)")
                // A junção não depende de qual dos lados é o local.
                #expect(TextMerge.merge(base: baseText, local: remoteText, remote: localText) == expected)
                if expected == nil { collided += 1 } else { merged += 1 }
            }
        }
        // Os dois resultados acontecem de verdade: a varredura não passa por falta de casos.
        #expect(merged > 0 && collided > 0)
    }
}
