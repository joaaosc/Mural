import MuralKit
import SwiftUI

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
        }
    }

    /// Uma prévia curta do que foi lido: a primeira linha do texto (até ``previewLimit`` caracteres), o site do primeiro
    /// link, o nome do primeiro arquivo ou o título do primeiro item de música. `nil` sem leitura e para imagem e PDF.
    static func preview(of content: ClipboardContent?) -> String? {
        switch content {
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
    /// "Colar 3 links", "Colar imagem", "Colar PDF", "Colar 2 arquivos", "Colar música", "Colar texto" antes de ler).
    static func title(of option: PasteOption, clipboard kind: ClipboardKind) -> String {
        switch option.action {
        case .text(let cardKind): "Colar como \(cardKind.creationTitle)"
        case .asRead, .read: "Colar \(noun(for: kind))"
        }
    }

    /// O símbolo da linha de uma opção: o do tipo de cartão que sai, ou `clipboard` quando não se sabe.
    static func symbol(of option: PasteOption) -> String {
        option.kind?.creationSymbol ?? "clipboard"
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

/// A seção do painel entre a vitrine e o rodapé: o que está copiado, as maneiras de colar no mural do centro e, quando
/// há um colar em andamento, feito ou falho, a linha de estado.
///
/// Só desenha: o teclado (↑/↓, Return, ⌘V) é do contêiner da vitrine, e quem lê a área de transferência é o modelo. O
/// clique numa opção a escolhe e cola por `choose`, que precisa ler a área de transferência de forma síncrona.
struct PasteSection: View {
    let model: MenuBarPanelModel
    /// Escolhe a opção do índice e cola.
    let choose: @MainActor (Int) -> Void

    @Namespace private var selectionPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.options.isEmpty {
                emptyNote
            } else {
                copiedLine
                optionRows
            }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PanelMetrics.contentPadding)
        .padding(.bottom, PanelMetrics.contentSpacing)
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-bar-paste-section")
    }

    // MARK: Copiado

    /// "Copiado: Texto · Comprar pão": o tipo e, quando o conteúdo já foi lido, uma prévia curta.
    private var copiedLine: some View {
        let kind = model.clipboardKind
        return HStack(spacing: 6) {
            Image(systemName: PasteDescription.symbol(for: kind))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Copiado:")
                .foregroundStyle(.secondary)
            Text(PasteDescription.name(for: kind))
                .fontWeight(.medium)
            if let preview = PasteDescription.preview(of: model.clipboardContent) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        // O mesmo recuo do conteúdo das linhas de opção, para o símbolo ficar na mesma coluna.
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    private var emptyNote: some View {
        Text(PasteDescription.emptyMessage(for: model.clipboard))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
    }

    // MARK: Opções

    /// Uma linha por maneira de colar; a escolhida leva o destaque e a dica do Return. A dica ocupa o mesmo espaço em todas
    /// as linhas (só some da vista), para a largura delas não mudar ao trocar de escolha.
    private var optionRows: some View {
        let kind = model.clipboardKind
        let destination = "em \(model.selectedEntry?.manifest.name ?? "")"
        return VStack(spacing: 2) {
            ForEach(Array(model.options.enumerated()), id: \.element.id) { index, option in
                let isSelected = index == model.selectedOption
                let title = PasteDescription.title(of: option, clipboard: kind)
                HStack(spacing: 6) {
                    PanelActionRow(
                        symbolName: PasteDescription.symbol(of: option),
                        title: title,
                        summary: destination,
                        isSelected: isSelected,
                        namespace: selectionPill,
                        help: "\(title) \(destination)",
                        accessibilityLabel: "\(title) \(destination)",
                        accessibilityHint: "Cola o que foi copiado no mural do centro da vitrine.",
                        action: { choose(index) }
                    )
                    .focusable(false)
                    .accessibilityIdentifier("menu-bar-paste-option-\(option.id)")

                    KeyHint(symbol: "return", label: "Colar", description: "Return cola o que foi copiado", isCompact: true)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(!isSelected)
                }
            }
        }
        .animation(PanelMotion.animation(PanelMotion.selection, reduceMotion: reduceMotion), value: model.selectedOption)
    }

    // MARK: Estado

    @ViewBuilder
    private var statusLine: some View {
        switch model.pasteStatus {
        case .idle:
            EmptyView()
        case .pasting:
            statusRow("Colando…") { ProgressView().controlSize(.small) }
        case .pasted(let message):
            statusRow(message) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        case .failed(let message):
            statusRow(message) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }
    }

    private func statusRow<Icon: View>(_ message: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 6) {
            icon()
                .frame(width: 16, height: 16)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menu-bar-paste-status")
    }
}
