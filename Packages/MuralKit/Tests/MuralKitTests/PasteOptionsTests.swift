import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@Suite("Opções de colar")
struct PasteOptionsTests {
    private func option(_ action: PasteOption.Action, _ kind: ItemKind?, _ count: Int, suggested: Bool) -> PasteOption {
        PasteOption(action: action, kind: kind, count: count, isSuggested: suggested)
    }

    private let shortText = "Ligar para o marceneiro"
    private let longText = String(repeating: "palavra ", count: 40)
    private let listText = "Compras da obra\n- [ ] Tinta azul\n- [ ] Rolo"

    // MARK: options

    @Test("Área de transferência vazia não tem opção")
    func nothingHasNoOptions() {
        #expect(PasteOptions.options(for: .nothing).isEmpty)
    }

    @Test("Links já lidos: uma opção que cola os cartões de link, com a contagem")
    func readLinks() {
        #expect(PasteOptions.options(for: .links(count: 3)) == [option(.asRead, .link, 3, suggested: true)])
        #expect(PasteOptions.options(for: .links(count: 1)) == [option(.asRead, .link, 1, suggested: true)])
    }

    @Test("Links ainda não lidos: uma opção que lê na hora, de cartão de link e sem contagem")
    func unreadLinks() {
        #expect(PasteOptions.options(for: .links(count: 0)) == [option(.read, .link, 0, suggested: true)])
    }

    @Test("Imagem e PDF: uma opção de um cartão do tipo certo")
    func imageAndPDF() {
        #expect(PasteOptions.options(for: .image) == [option(.asRead, .image, 1, suggested: true)])
        #expect(PasteOptions.options(for: .pdf) == [option(.asRead, .pdf, 1, suggested: true)])
    }

    @Test("Arquivos lidos: uma opção sem tipo fixo (varia por arquivo) e com a contagem")
    func readFiles() {
        #expect(PasteOptions.options(for: .files(count: 4)) == [option(.asRead, nil, 4, suggested: true)])
    }

    @Test("Arquivos ainda não lidos: uma opção que lê na hora, sem tipo e sem contagem")
    func unreadFiles() {
        #expect(PasteOptions.options(for: .files(count: 0)) == [option(.read, nil, 0, suggested: true)])
    }

    @Test("Música lida: uma opção que cola os cartões de música, com a contagem; sem ler, uma que lê na hora")
    func music() {
        #expect(PasteOptions.options(for: .music(count: 2)) == [option(.asRead, .music, 2, suggested: true)])
        #expect(PasteOptions.options(for: .music(count: 0)) == [option(.read, .music, 0, suggested: true)])
    }

    @Test("Texto ainda não lido: uma opção que lê na hora, sem tipo e sem contagem")
    func unreadText() {
        #expect(PasteOptions.options(for: .text(nil)) == [option(.read, nil, 0, suggested: true)])
    }

    @Test("Contagem negativa vale como ainda não lido", arguments: [-1, -50])
    func negativeCountsAreUnread(count: Int) {
        #expect(PasteOptions.options(for: .links(count: count)) == [option(.read, .link, 0, suggested: true)])
        #expect(PasteOptions.options(for: .files(count: count)) == [option(.read, nil, 0, suggested: true)])
    }

    @Test("Texto em branco não tem opção", arguments: ["", " ", "   \n  ", "\t\n\r\n"])
    func blankTextHasNoOptions(text: String) {
        #expect(PasteOptions.options(for: .text(text)).isEmpty)
    }

    @Test("Texto curto: post-it sugerido, nota como alternativa e nada de lista")
    func shortTextSuggestsSticky() {
        let options = PasteOptions.options(for: .text(shortText))

        #expect(
            options == [
                option(.text(.sticky), .sticky, 1, suggested: true),
                option(.text(.text), .text, 1, suggested: false),
            ])
    }

    @Test("Texto longo: nota sugerida, com o post-it como alternativa")
    func longTextSuggestsNote() {
        let options = PasteOptions.options(for: .text(longText))

        #expect(
            options == [
                option(.text(.sticky), .sticky, 1, suggested: false),
                option(.text(.text), .text, 1, suggested: true),
            ])
    }

    @Test("Texto que parece lista: três opções, na ordem dos botões, com a lista sugerida")
    func listTextOffersAChecklist() {
        let options = PasteOptions.options(for: .text(listText))

        #expect(
            options == [
                option(.text(.sticky), .sticky, 1, suggested: false),
                option(.text(.text), .text, 1, suggested: false),
                option(.text(.checklist), .checklist, 1, suggested: true),
            ])
    }

    @Test("As opções de texto seguem o classificador: mesma ordem e mesma sugestão")
    func textOptionsFollowTheClassifier() {
        for text in [shortText, longText, listText, "Só um item\n- pão", "Compras\n- pão\n- leite"] {
            let choice = ContentClassifier.pasteChoice(forText: text)

            let options = PasteOptions.options(for: .text(text))

            #expect(options.map(\.kind) == choice.options.map { Optional($0) }, "\(text.debugDescription)")
            #expect(options.map(\.action) == choice.options.map { PasteOption.Action.text($0) })
            #expect(options.filter(\.isSuggested).map(\.kind) == [choice.suggested], "\(text.debugDescription)")
            #expect(options.allSatisfy { $0.count == 1 })
        }
    }

    @Test("Um item só com marcador não é lista: sem a opção de lista")
    func singleBulletIsNotAChecklist() {
        let options = PasteOptions.options(for: .text("Só um item\n- pão"))

        #expect(options.map(\.kind) == [.sticky, .text])
        #expect(options.filter(\.isSuggested).map(\.kind) == [.sticky])
    }

    @Test("Espaços e quebras de linha nas pontas não atrapalham a classificação")
    func surroundingWhitespaceIsIgnored() {
        let options = PasteOptions.options(for: .text("\n\n  Compras\n- pão\n- leite\n\n  "))

        #expect(options.map(\.kind) == [.sticky, .text, .checklist])
        #expect(options.filter(\.isSuggested).map(\.kind) == [.checklist])
    }

    @Test("Uma opção única é sempre a sugerida")
    func singleOptionIsAlwaysSuggested() {
        let single: [ClipboardKind] = [
            .links(count: 2), .links(count: 0), .image, .pdf, .files(count: 3), .files(count: 0), .text(nil),
        ]

        for kind in single {
            let options = PasteOptions.options(for: kind)
            #expect(options.count == 1 && options[0].isSuggested, "\(kind)")
        }
    }

    @Test("O id é estável por ação: asRead, read e text-<tipo>")
    func identifiers() {
        #expect(option(.asRead, .image, 1, suggested: true).id == "asRead")
        #expect(option(.read, nil, 0, suggested: true).id == "read")
        #expect(option(.text(.sticky), .sticky, 1, suggested: true).id == "text-sticky")
        #expect(option(.text(.text), .text, 1, suggested: false).id == "text-text")
        #expect(option(.text(.checklist), .checklist, 1, suggested: false).id == "text-checklist")

        let ids = PasteOptions.options(for: .text(listText)).map(\.id)
        #expect(ids == ["text-sticky", "text-text", "text-checklist"])
        #expect(Set(ids).count == ids.count, "sem repetição na mesma lista")
    }

    @Test("O id não muda com a contagem nem com a sugestão")
    func identifiersIgnoreCountAndSuggestion() {
        #expect(option(.asRead, .link, 1, suggested: true).id == option(.asRead, nil, 9, suggested: false).id)
        #expect(PasteOptions.options(for: .text(shortText)).map(\.id) == PasteOptions.options(for: .text(longText)).map(\.id))
    }

    // MARK: suggestedIndex

    @Test("Sem opções, não há posição sugerida")
    func suggestedIndexOfNoOptions() {
        #expect(PasteOptions.suggestedIndex(in: []) == nil)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .nothing)) == nil)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .text("  "))) == nil)
    }

    @Test("A posição sugerida é a da opção marcada")
    func suggestedIndexFollowsTheSuggestion() {
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .text(shortText))) == 0)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .text(longText))) == 1)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .text(listText))) == 2)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .image)) == 0)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .links(count: 2))) == 0)
        #expect(PasteOptions.suggestedIndex(in: PasteOptions.options(for: .text(nil))) == 0)
    }

    @Test("Sem nenhuma marcada, a primeira; com mais de uma marcada, a primeira delas")
    func suggestedIndexFallbacks() {
        let none = [option(.text(.sticky), .sticky, 1, suggested: false), option(.text(.text), .text, 1, suggested: false)]
        #expect(PasteOptions.suggestedIndex(in: none) == 0)

        let two = [
            option(.text(.sticky), .sticky, 1, suggested: false), option(.text(.text), .text, 1, suggested: true),
            option(.text(.checklist), .checklist, 1, suggested: true),
        ]
        #expect(PasteOptions.suggestedIndex(in: two) == 1)
    }
}

@Suite("Palpite da área de transferência")
struct ClipboardKindTests {
    // MARK: isRead

    @Test(
        "isRead é falso só para o que se sabe pelo tipo: links e arquivos sem contagem e texto sem o texto",
        arguments: [
            (ClipboardKind.nothing, true), (.image, true), (.pdf, true),
            (.links(count: 2), true), (.links(count: 0), false),
            (.files(count: 2), true), (.files(count: 0), false),
            (.text("oi"), true), (.text(""), true), (.text("   "), true), (.text(nil), false),
            (.music(count: 1), true), (.music(count: 0), false),
        ])
    func isReadByKind(kind: ClipboardKind, expected: Bool) {
        #expect(kind.isRead == expected, "\(kind)")
    }

    // MARK: Música

    @Test(
        "Os tipos do app Música valem mais que tudo, como no ⌘V, que lê o Música antes do resto",
        arguments: ["com.apple.musicui.genericmusicitem", "com.apple.tv.metadata", "com.apple.music.playlist.name"])
    func musicTypesComeFirst(musicType: String) {
        #expect(ClipboardKind.hint(typeIdentifiers: [musicType]) == .music(count: 0))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", musicType]) == .music(count: 0))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.url", "public.png", musicType]) == .music(count: 0))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.file-url", musicType], fileContentType: "public.png") == .music(count: 0))
    }

    @Test("Um link sozinho continua link no palpite: só a leitura diz se é do Apple Music")
    func appleMusicLinksAreLinksUntilRead() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.url", "public.utf8-plain-text"]) == .links(count: 0))
    }

    // MARK: Arquivos

    @Test("Arquivo vale mais que qualquer outro tipo, e sem o tipo do arquivo ainda não se sabe o que é")
    func fileURLComesFirst() {
        let everything = ["public.png", "com.adobe.pdf", "public.url", "public.utf8-plain-text", "public.file-url", "public.tiff"]

        #expect(ClipboardKind.hint(typeIdentifiers: everything) == .files(count: 0))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", "public.file-url"]) == .files(count: 0))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.file-url"], fileContentType: nil) == .files(count: 0))
    }

    @Test(
        "O tipo do arquivo decide: imagem vira imagem, PDF vira PDF e o resto segue como arquivos",
        arguments: [
            ("public.png", ClipboardKind.image), ("public.jpeg", .image), ("public.heic", .image), ("public.svg-image", .image),
            ("public.image", .image), ("com.adobe.pdf", .pdf),
            ("public.mpeg-4", .files(count: 0)), ("public.plain-text", .files(count: 0)), ("public.folder", .files(count: 0)),
            ("public.data", .files(count: 0)), ("com.example.desconhecido", .files(count: 0)), ("", .files(count: 0)),
        ])
    func fileContentTypeDecides(identifier: String, expected: ClipboardKind) {
        let hint = ClipboardKind.hint(typeIdentifiers: ["public.file-url", "public.utf8-plain-text"], fileContentType: identifier)
        #expect(hint == expected, "\(identifier)")
    }

    @Test("O tipo do arquivo só conta quando a área de transferência tem mesmo um arquivo")
    func fileContentTypeIsIgnoredWithoutAFileURL() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text"], fileContentType: "public.png") == .text(nil))
        #expect(ClipboardKind.hint(typeIdentifiers: [], fileContentType: "com.adobe.pdf") == .nothing)
    }

    // MARK: Imagens e PDF

    @Test("PNG é imagem, mesmo com endereço e texto junto (Copiar Imagem do Safari)")
    func pngWinsOverLinksAndText() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.png"]) == .image)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.url", "public.utf8-plain-text", "public.png", "public.tiff"]) == .image)
    }

    @Test("PDF é PDF, mesmo com texto junto")
    func pdf() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["com.adobe.pdf"]) == .pdf)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", "com.adobe.pdf"]) == .pdf)
    }

    @Test("A prioridade não depende da ordem da lista: PNG antes de PDF, PDF antes das outras imagens")
    func priorityDoesNotFollowTheListOrder() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["com.adobe.pdf", "public.png"]) == .image)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.png", "com.adobe.pdf"]) == .image)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.tiff", "com.adobe.pdf"]) == .pdf)
        #expect(ClipboardKind.hint(typeIdentifiers: ["com.adobe.pdf", "public.tiff"]) == .pdf)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", "public.png"]) == .image)
    }

    @Test(
        "TIFF, JPEG, HEIC e GIF são imagens, também quando vêm com endereço e texto",
        arguments: ["public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"])
    func convertibleImages(identifier: String) {
        #expect(ClipboardKind.hint(typeIdentifiers: [identifier]) == .image)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.url", "public.utf8-plain-text", identifier]) == .image)
    }

    @Test("Qualquer outro tipo de imagem também é imagem, e vale mais que o texto que vem junto, como no ⌘V")
    func otherImageTypesBeatText() {
        for identifier in [UTType.bmp.identifier, UTType.svg.identifier, UTType.rawImage.identifier, "public.image"] {
            #expect(ClipboardKind.hint(typeIdentifiers: [identifier]) == .image, "\(identifier)")
            #expect(ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", identifier]) == .image, "\(identifier)")
        }
    }

    // MARK: Links e texto

    @Test(
        "Endereços da web viram links ainda sem contagem",
        arguments: ["public.url", "com.apple.Safari.bookmarkDictionaryList", "WebURLsWithTitlesPboardType"])
    func links(identifier: String) {
        #expect(ClipboardKind.hint(typeIdentifiers: [identifier]) == .links(count: 0))
        #expect(
            ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text", identifier]) == .links(count: 0), "o link vale mais que o texto")
    }

    @Test("Imagem vale mais que o endereço que vem junto")
    func imageBeatsLinks() {
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.url", "public.tiff"]) == .image)
        #expect(ClipboardKind.hint(typeIdentifiers: ["WebURLsWithTitlesPboardType", "public.jpeg"]) == .image)
    }

    @Test(
        "Texto simples vira texto ainda não lido, também com formatos ricos junto",
        arguments: ["public.utf8-plain-text", "public.plain-text"])
    func plainText(identifier: String) {
        #expect(ClipboardKind.hint(typeIdentifiers: [identifier]) == .text(nil))
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.rtf", "public.html", identifier]) == .text(nil))
    }

    // MARK: Nada

    @Test(
        "Sem tipo que o ⌘V entenda, não há o que colar",
        arguments: [[], ["com.example.desconhecido"], ["public.data"], ["public.mpeg-4"], [""]])
    func unknownTypesAreNothing(identifiers: [String]) {
        #expect(ClipboardKind.hint(typeIdentifiers: identifiers) == .nothing)
    }

    @Test("Só o que foi lido de verdade conta: o palpite de links, arquivos e texto ainda não foi lido")
    func hintsOfLinksFilesAndTextAreUnread() {
        #expect(!ClipboardKind.hint(typeIdentifiers: ["public.url"]).isRead)
        #expect(!ClipboardKind.hint(typeIdentifiers: ["public.file-url"]).isRead)
        #expect(!ClipboardKind.hint(typeIdentifiers: ["public.utf8-plain-text"]).isRead)
        #expect(ClipboardKind.hint(typeIdentifiers: ["public.png"]).isRead)
        #expect(ClipboardKind.hint(typeIdentifiers: ["com.adobe.pdf"]).isRead)
        #expect(ClipboardKind.hint(typeIdentifiers: []).isRead)
    }

    @Test("Do palpite às opções: cada palpite já tem as opções do painel")
    func hintsFeedTheOptions() {
        let table: [([String], [PasteOption.Action])] = [
            (["public.png"], [.asRead]), (["com.adobe.pdf"], [.asRead]), (["public.url"], [.read]),
            (["public.file-url"], [.read]), (["public.utf8-plain-text"], [.read]), ([], []),
            (["com.apple.tv.metadata", "public.utf8-plain-text"], [.read]),
        ]

        for (identifiers, actions) in table {
            let options = PasteOptions.options(for: ClipboardKind.hint(typeIdentifiers: identifiers))
            #expect(options.map(\.action) == actions, "\(identifiers)")
        }
    }
}
