import Foundation
import MuralKit

/// Os textos da seção "Copiado" do painel: o nome do tipo, a prévia curta, o título de cada opção e as frases de quando
/// não há o que colar. Sem SwiftUI, para serem conferidos sem desenhar nada.
enum PasteDescription {
    /// O tamanho máximo, em caracteres, da prévia de um texto.
    static let previewLimit = 60

    /// O tipo em minúsculas, como entra em "Colar …": "texto", "link", "3 links", "imagem", "PDF", "2 arquivos", "música".
    /// Sem a contagem lida (zero) ou com um só, fica no singular.
    static func noun(for kind: ClipboardKind) -> String {
        switch kind {
        case .nothing: "nada"
        case .text: "texto"
        case .links(let count): count > 1 ? "\(count) links" : "link"
        case .image: "imagem"
        case .pdf: "PDF"
        case .files(let count): count > 1 ? "\(count) arquivos" : "arquivo"
        case .music(let count): count > 1 ? "\(count) músicas" : "música"
        case .contact(let count): count > 1 ? "\(count) contatos" : "contato"
        }
    }

    /// O nome do tipo na linha "Copiado:": "Texto", "Link", "3 links", "Imagem", "PDF", "2 arquivos", "Música", "4 músicas".
    static func name(for kind: ClipboardKind) -> String {
        let text = noun(for: kind)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// O símbolo do tipo na linha "Copiado:"; `clipboard` para o que não tem um tipo de cartão só (arquivos).
    static func symbol(for kind: ClipboardKind) -> String {
        switch kind {
        case .nothing, .files: "clipboard"
        case .text: ItemKind.text.creationSymbol
        case .links: ItemKind.link.creationSymbol
        case .image: ItemKind.image.creationSymbol
        case .pdf: ItemKind.pdf.creationSymbol
        case .music: ItemKind.music.creationSymbol
        case .contact: ItemKind.contact.creationSymbol
        }
    }

    /// Uma prévia curta do que foi lido: a primeira linha do texto (até ``previewLimit`` caracteres), o site do primeiro
    /// link, o nome do primeiro arquivo ou o título do primeiro item de música. `nil` sem leitura e para imagem e PDF.
    static func preview(of content: ClipboardContent?) -> String? {
        switch content {
        case .contacts(let drafts)?:
            return drafts.first.flatMap { nonBlank($0.snapshot.displayName) }
        case .music(let drafts)?:
            return drafts.first.flatMap { nonBlank($0.snapshot.title) }
        case .pasted(.text(let text))?:
            return firstLine(of: text)
        case .pasted(.links(let links))?:
            return links.first.map { WebLink.displayHost(of: $0.url) }
        case .pasted(.files(let urls))?:
            return urls.first.flatMap { nonBlank($0.lastPathComponent) }
        case .pasted(.data)?, .pasted(.imageNeedingConversion)?, .pasted(.nothing)?, nil:
            return nil
        }
    }

    /// O título da linha de uma opção: "Colar como Sticker" para texto; para o resto, "Colar" e o tipo ("Colar link",
    /// "Colar 3 links", "Colar imagem", "Colar PDF", "Colar 2 arquivos", "Colar música", "Colar texto" antes de ler). A opção
    /// de editar se chama "Editar antes de colar".
    static func title(of option: PasteOption, clipboard kind: ClipboardKind) -> String {
        switch option.action {
        case .text(let cardKind): "Colar como \(cardKind.creationTitle)"
        case .asRead, .read: "Colar \(noun(for: kind))"
        case .edit: "Editar antes de colar"
        }
    }

    /// O título do botão de colar do editor de texto: o da opção que o classificador sugere para esse texto ("Colar como
    /// Sticker", "Colar como Lista"…), que muda enquanto se digita; "Colar" com o texto em branco.
    static func editorPasteTitle(for text: String) -> String {
        let kind = ClipboardKind.text(text)
        guard let suggested = PasteOptions.options(for: kind).first(where: \.isSuggested) else { return "Colar" }
        return title(of: suggested, clipboard: kind)
    }

    /// O rótulo da linha de cima: "Copiado:" ou, com o texto mudado no editor do painel, "Editado:".
    static func copiedLabel(isEdited: Bool = false) -> String {
        isEdited ? "Editado:" : "Copiado:"
    }

    /// O nome curto da tecla Return na linha escolhida: "Colar" ou, na de editar, "Editar".
    static func returnHintLabel(of option: PasteOption) -> String {
        switch option.action {
        case .asRead, .read, .text: "Colar"
        case .edit: "Editar"
        }
    }

    /// O que o Return faz na linha escolhida, para a dica de ferramenta e a de acessibilidade da tecla.
    static func returnHintDescription(of option: PasteOption) -> String {
        switch option.action {
        case .asRead, .read, .text: "Return cola o que foi copiado"
        case .edit: "Return abre o editor"
        }
    }

    /// A dica de acessibilidade da linha de uma opção: o que acontece ao pressioná-la.
    static func accessibilityHint(of option: PasteOption) -> String {
        switch option.action {
        case .asRead, .read, .text: "Cola o que foi copiado no mural do centro da vitrine."
        case .edit: "Abre um editor aqui no painel para mudar o texto antes de colar."
        }
    }

    /// O símbolo da linha de uma opção: o lápis da edição (`square.and.pencil`) na de editar; nas demais, o do tipo de cartão
    /// que sai, ou `clipboard` quando não se sabe.
    static func symbol(of option: PasteOption) -> String {
        switch option.action {
        case .edit: "square.and.pencil"
        case .asRead, .read, .text: option.kind?.creationSymbol ?? "clipboard"
        }
    }

    /// A frase de quando não há opções de colar, conforme o que se sabe da área de transferência.
    static func emptyMessage(for state: ClipboardState) -> String {
        switch state {
        case .protected:
            "O que está copiado é privado (como uma senha) e o Mural não o lê."
        case .deniedBySystem:
            "O macOS não deixa o Mural ver o que foi copiado. O ⌘V ainda cola; para ver a prévia, permita o Mural em "
                + "Ajustes do Sistema › Privacidade e Segurança › Colar de Outros Apps."
        case .nothing, .available:
            "Copie um link, uma imagem, um texto ou uma música para colar num mural."
        }
    }

    // MARK: Formatação

    /// O título da linha de uma formatação. As de maiúsculas e minúsculas se escrevem como o resultado, para a pessoa ver
    /// o efeito no próprio nome.
    static func title(of format: PasteTextFormat) -> String {
        format.title
    }

    /// O símbolo da linha de uma formatação.
    static func symbol(of format: PasteTextFormat) -> String {
        format.symbolName
    }

    /// A prévia de uma formatação: a primeira linha do texto já formatado, encurtada como a prévia do que foi copiado.
    /// Sem o texto (ainda não lido), avisa que ela vale para o que o colar ler.
    static func formatPreview(of formattedText: String?) -> String {
        guard let formattedText else { return "vale para o texto ao colar" }
        return firstLine(of: formattedText) ?? ""
    }

    /// A linha de cima da etapa de formatação: a maneira de colar escolhida e o mural, como "Colar como Sticker em Casa".
    static func chosenOption(_ option: PasteOption, clipboard kind: ClipboardKind, board: String) -> String {
        "\(title(of: option, clipboard: kind)) em \(board)"
    }

    private static func firstLine(of text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.first(where: { !$0.isEmpty }) else { return nil }
        guard line.count > previewLimit else { return line }
        return line.prefix(previewLimit).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
