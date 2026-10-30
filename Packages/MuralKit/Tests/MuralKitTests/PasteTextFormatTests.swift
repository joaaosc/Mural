import Foundation
import Testing

@testable import MuralKit

@Suite("Formatação do texto colado pelo painel")
struct PasteTextFormatTests {
    private let portuguese = Locale(identifier: "pt_BR")

    private func format(_ format: PasteTextFormat, _ text: String) -> String {
        format.apply(to: text, locale: portuguese)
    }

    @Test("A ordem é a do painel, com o texto como foi copiado primeiro, e ele não muda nada")
    func orderStartsWithTheUntouchedText() {
        #expect(
            PasteTextFormat.allCases == [.original, .tidy, .joinedLines, .bulletList, .taskList, .lowercase, .uppercase])
        let messy = "  Olá,   mundo \r\n\n\n\t- item  "
        #expect(format(.original, messy) == messy)
    }

    @Test("Limpar espaços tira as pontas, junta os espaços e deixa no máximo uma linha vazia entre parágrafos")
    func tidyCollapsesSpacesAndBlankLines() {
        #expect(format(.tidy, "\n\n  Olá,   mundo  \n\n\n\t segunda\t\tlinha \n\n") == "Olá, mundo\n\nsegunda linha")
        #expect(format(.tidy, "a\r\nb\rc") == "a\nb\nc", "quebras do Windows e do Mac antigo viram uma linha cada")
        #expect(format(.tidy, "a\u{00A0}\u{00A0}b\u{200B}c\u{FEFF}") == "a bc", "espaço sem quebra e invisíveis")
        #expect(format(.tidy, "família 👨‍👩‍👧") == "família 👨‍👩‍👧", "o juntor de largura zero do emoji fica")
    }

    @Test("Juntar linhas põe cada parágrafo numa linha e mantém o hífen de uma palavra partida")
    func joinedLinesKeepsParagraphs() {
        let pdf = "Uma frase que\n  quebrou no meio.\n\n\nOutro parágrafo\naqui."
        #expect(format(.joinedLines, pdf) == "Uma frase que quebrou no meio.\n\nOutro parágrafo aqui.")
        #expect(format(.joinedLines, "exem-\nplo de bem-\nvindo") == "exem-plo de bem-vindo")
        #expect(format(.joinedLines, "isto -\naquilo") == "isto - aquilo", "um travessão solto não é hífen de palavra")
    }

    @Test("Lista com marcadores: um item por linha, sem o marcador antigo e sem linhas vazias")
    func bulletListReplacesOldMarkers() {
        let mixed = "ovos\n\n- leite\n* pão\n1. café\n12) açúcar\n• sal\n[x] feito\n-5 graus\n-"
        #expect(format(.bulletList, mixed) == "- ovos\n- leite\n- pão\n- café\n- açúcar\n- sal\n- feito\n- -5 graus")
    }

    @Test("Lista de tarefas: caixa vazia em cada item, e o que já vinha marcado continua marcado")
    func taskListKeepsCheckedItems() {
        let tasks = "- [x] feito\n[ ] a fazer\ncomprar pão\n- [X] também feito\n- [ ]"
        #expect(format(.taskList, tasks) == "- [x] feito\n- [ ] a fazer\n- [ ] comprar pão\n- [x] também feito")
        #expect(format(.taskList, "[x]colado") == "- [ ] [x]colado", "sem espaço depois, não é uma caixa")
    }

    @Test("A lista de tarefas sai como lista para o mural")
    func taskListLooksLikeAChecklist() {
        let formatted = format(.taskList, "ovos\nleite\npão")
        #expect(ChecklistParser.looksLikeChecklist(formatted))
    }

    @Test("Minúsculas e maiúsculas seguem o idioma, acentos inclusive")
    func caseChangesKeepAccents() {
        #expect(format(.lowercase, "Ação ÉPICA no Pará") == "ação épica no pará")
        #expect(format(.uppercase, "Ação épica no Pará") == "AÇÃO ÉPICA NO PARÁ")
    }

    @Test("Aplicar duas vezes dá o mesmo que aplicar uma")
    func formatsAreIdempotent() {
        let samples = ["  a   b \n\n\n c ", "- [x] um\n2. dois\n• três", "linha\nquebrada\n\noutra", "MiStUrA"]
        for format in PasteTextFormat.allCases {
            for sample in samples {
                let once = self.format(format, sample)
                #expect(self.format(format, once) == once, "\(format) não é estável em \(sample.debugDescription)")
            }
        }
    }

    @Test("Texto só de espaços não vira conteúdo em nenhuma formatação que mexe em espaços")
    func blankTextStaysBlank() {
        for format in [PasteTextFormat.tidy, .joinedLines, .bulletList, .taskList] {
            #expect(self.format(format, "  \n\t \u{200B}\n ").isEmpty, "\(format)")
        }
    }

    @Test("Lista com marcadores e de tarefas convertem linhas numeradas e com marcadores misturados; o resto não muda")
    func listsConvertNumberedAndBulleted() {
        let text = "1. Pão\n2) Leite\n• Café\n- [x] Chá\n10. Açúcar\n1-sem marcador"
        #expect(format(.bulletList, text) == "- Pão\n- Leite\n- Café\n- Chá\n- Açúcar\n- 1-sem marcador")
        #expect(format(.taskList, text) == "- [ ] Pão\n- [ ] Leite\n- [ ] Café\n- [x] Chá\n- [ ] Açúcar\n- [ ] 1-sem marcador")
        #expect(format(.tidy, "1.   Pão  \n\n\n2.  Leite") == "1. Pão\n\n2. Leite")
        #expect(format(.joinedLines, "1. Pão\n2. Leite") == "1. Pão 2. Leite")
    }

    // MARK: Seleção

    private func selected(_ text: String, _ needle: String) -> Range<String.Index> {
        text.range(of: needle)!
    }

    @Test("Com seleção só o trecho muda e a nova seleção cobre o trecho trocado")
    func partialSelectionOnMultilineText() {
        let text = "primeira\nsegunda\nterceira"
        let result = PasteTextFormat.uppercase.apply(to: text, selection: selected(text, "segunda"), locale: portuguese)
        #expect(result.text == "primeira\nSEGUNDA\nterceira")
        #expect(result.text[result.selection] == "SEGUNDA")

        let list = PasteTextFormat.bulletList.apply(to: "a\nb\nc", selection: selected("a\nb\nc", "b\nc"), locale: portuguese)
        #expect(list.text == "a\n- b\n- c" && list.text[list.selection] == "- b\n- c")
    }

    @Test("Selecionar o meio de uma palavra põe só esse pedaço em maiúsculas")
    func selectionInsideAWord() {
        let text = "paralelepípedo"
        let result = PasteTextFormat.uppercase.apply(to: text, selection: selected(text, "lele"), locale: portuguese)
        #expect(result.text == "paraLELEpípedo" && result.text[result.selection] == "LELE")
    }

    @Test("Sem seleção, ou com ela vazia, vale o texto inteiro")
    func wholeTextWithoutSelection() {
        let none = PasteTextFormat.uppercase.apply(to: "ola mundo", selection: nil, locale: portuguese)
        #expect(none.text == "OLA MUNDO" && none.selection == none.text.startIndex..<none.text.endIndex)
        let text = "ola"
        let empty = PasteTextFormat.uppercase.apply(to: text, selection: text.startIndex..<text.startIndex, locale: portuguese)
        #expect(empty.text == "OLA" && empty.selection == empty.text.startIndex..<empty.text.endIndex)
    }

    @Test("Um resultado só de espaços mantém o original, no texto todo e na seleção")
    func emptyResultKeepsTheOriginal() {
        let invisible = "\u{200B}\u{200B}"
        #expect(PasteTextFormat.tidy.applyKeepingNonEmpty(to: invisible) == invisible)
        let result = PasteTextFormat.tidy.apply(to: invisible, selection: invisible.startIndex..<invisible.endIndex)
        #expect(result.text == invisible && result.text[result.selection] == invisible)
    }

    @Test("Cada formatação tem título e símbolo")
    func titlesAndSymbols() {
        #expect(PasteTextFormat.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbolName.isEmpty })
        #expect(PasteTextFormat.original.title == "Como está" && PasteTextFormat.uppercase.symbolName == "textformat.size.larger")
    }

    @Test("A quebra de linha da ponta da seleção fica como estava")
    func selectionEdgesAreKept() {
        let text = "primeira\nsegunda\nterceira"
        let upper = PasteTextFormat.uppercase.apply(to: text, selection: selected(text, "segunda\n"), locale: portuguese)
        #expect(upper.text == "primeira\nSEGUNDA\nterceira" && upper.text[upper.selection] == "SEGUNDA")
        let list = PasteTextFormat.bulletList.apply(to: text, selection: selected(text, "segunda\n"), locale: portuguese)
        #expect(list.text == "primeira\n- segunda\nterceira" && list.text[list.selection] == "- segunda")
        let blank = PasteTextFormat.uppercase.apply(to: "a \n b", selection: selected("a \n b", " \n "))
        #expect(blank.text == "a \n b")
    }

    @Test("Formatações de linha ampliam a seleção para a linha inteira; maiúsculas e minúsculas não")
    func lineFormatsExpandTheSelection() {
        let text = "paralelepípedo"
        let list = PasteTextFormat.bulletList.apply(to: text, selection: selected(text, "lele"), locale: portuguese)
        #expect(list.text == "- paralelepípedo" && list.text[list.selection] == "- paralelepípedo")
        let tasks = PasteTextFormat.taskList.apply(to: "a\nbcd\nc", selection: selected("a\nbcd\nc", "c"), locale: portuguese)
        #expect(tasks.text == "a\n- [ ] bcd\nc")
        let lower = PasteTextFormat.lowercase.apply(to: "ABC DEF", selection: selected("ABC DEF", "BC D"), locale: portuguese)
        #expect(lower.text == "Abc dEF" && lower.text[lower.selection] == "bc d")
    }
}
