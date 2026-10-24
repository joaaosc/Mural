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
}
