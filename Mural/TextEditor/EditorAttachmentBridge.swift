import AppKit
import MuralKit
import StretchText

/// Mantém o texto mostrado no `NSTextView` do editor em sincronia com o Markdown do documento.
///
/// No Markdown, cada cartão embutido e cada imagem ainda não gravada é uma linha `![título](mural-card:<UUID>)` ou
/// `![…](mural-colando:<TOKEN>)`. Na tela, essa linha é UM anexo (`EmbeddedTextAttachment`, um caractere U+FFFC). A ponte faz as
/// duas conversões e as edições que mexem nos anexos, sempre pelo caminho do `NSTextView` (`shouldChangeText`,
/// `replaceCharacters`, `didChangeText`), para o ⌘Z do próprio campo desfazer e refazer.
///
/// Só o TextKit 2 é usado: nada aqui lê `layoutManager`, que faria a view voltar ao TextKit 1 para sempre.
@MainActor
final class EditorAttachmentBridge {
    /// Acha o que mostrar para uma linha de bloco (`mural-card:` ou `mural-colando:`); `nil` quando o documento não tem o
    /// cartão ou a imagem, e então a linha fica como texto.
    typealias Resolver = @MainActor (_ line: String) -> EmbeddedTextAttachment.Content?

    /// O texto de volta em Markdown e, para cada posição do texto mostrado, onde ela cai no Markdown.
    struct Mapping {
        /// O Markdown, com cada anexo numa linha só dele.
        let markdown: String
        /// `offsets[i]` é a posição (em unidades UTF-16 do Markdown) de antes do caractere `i` do texto mostrado;
        /// o último valor é o tamanho do Markdown.
        let offsets: [Int]
    }

    private(set) weak var textView: NSTextView?
    /// Quem acha o conteúdo de cada linha de bloco; troca quando o campo passa a mostrar outro documento.
    var resolve: Resolver

    /// O último mapa calculado; vale até a próxima edição do texto (`didProcessEditing`), então um aviso de texto e um de seleção
    /// seguidos leem o texto uma vez só.
    private var cachedMapping: Mapping?
    private var storageObserver: (any NSObjectProtocol)?
    /// Os desenhos já feitos, por linha de Markdown: cada recarga refaz os anexos, e o desenho de uma linha não muda.
    private var pictures: [String: EmbeddedTextAttachment.Picture] = [:]

    init(resolve: @escaping Resolver) {
        self.resolve = resolve
    }

    isolated deinit {
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
    }

    /// Chamado ao montar o `NSTextView`.
    func attach(_ textView: NSTextView) {
        self.textView = textView
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cachedMapping = nil }
        }
    }

    /// O mapa do texto mostrado agora, do cache quando o texto não mudou desde a última leitura.
    func currentMapping() -> Mapping {
        if let cachedMapping { return cachedMapping }
        guard let storage = textView?.textStorage else { return Mapping(markdown: "", offsets: [0]) }
        let mapping = Self.mapping(of: storage)
        cachedMapping = mapping
        return mapping
    }

    // MARK: Conversões

    /// Verdadeiro para uma linha que é só `![…](mural-card:…)` ou `![…](mural-colando:…)`.
    static func isBlockLine(_ line: Substring) -> Bool {
        guard let image = MarkdownImage.parse(line) else { return false }
        return NoteImageMarkup.isCardSource(image.source) || NoteImageMarkup.isPendingSource(image.source)
    }

    /// O Markdown como texto mostrado: as linhas de bloco que o documento sabe resolver viram um anexo cada; o resto é texto.
    func render(_ markdown: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
            if Self.isBlockLine(line), let content = resolve(String(line)) {
                let piece = NSMutableAttributedString(attachment: attachment(for: String(line), content: content))
                piece.addAttributes(attributes.filter { $0.key != .attachment }, range: NSRange(location: 0, length: piece.length))
                result.append(piece)
            } else {
                result.append(NSAttributedString(string: String(line), attributes: attributes))
            }
        }
        return result
    }

    /// O texto mostrado de volta em Markdown, com o mapa de posições.
    ///
    /// Cada anexo vira a sua linha e fica sempre num bloco só dele: se há texto colado ao anexo (digitado antes ou depois dele),
    /// entra uma linha em branco, como em `NoteImageMarkup.insertion`. Um anexo sem a linha (colado de fora) não deixa nada.
    static func mapping(of attributed: NSAttributedString) -> Mapping {
        var buffer: [UInt16] = []
        var offsets: [Int] = []
        offsets.reserveCapacity(attributed.length + 1)
        var needsSeparator = false
        let newline = UInt16(10)
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let attachment = value as? EmbeddedTextAttachment {
                for _ in 0..<range.length {
                    if let last = buffer.last, last != newline { buffer.append(contentsOf: [newline, newline]) }
                    needsSeparator = false
                    offsets.append(buffer.count)
                    buffer.append(contentsOf: attachment.markdownLine.utf16)
                    needsSeparator = true
                }
                return
            }
            let units = Array((attributed.string as NSString).substring(with: range).utf16)
            for unit in units {
                if value != nil {
                    // Anexo de outra origem: sem linha, não deixa texto.
                    offsets.append(buffer.count)
                    continue
                }
                if needsSeparator, unit != newline { buffer.append(contentsOf: [newline, newline]) }
                needsSeparator = false
                offsets.append(buffer.count)
                buffer.append(unit)
            }
        }
        offsets.append(buffer.count)
        return Mapping(markdown: String(decoding: buffer, as: UTF16.self), offsets: offsets)
    }

    // MARK: Leitura do campo

    /// O Markdown do que está no campo.
    func markdown() -> String {
        currentMapping().markdown
    }

    /// A seleção do campo, em unidades UTF-16 do Markdown; `nil` sem campo.
    func markdownSelection() -> Range<Int>? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let selected = textView.selectedRange()
        guard selected.location != NSNotFound, selected.location + selected.length <= storage.length else { return nil }
        let offsets = currentMapping().offsets
        return offsets[selected.location]..<offsets[selected.location + selected.length]
    }

    /// O Markdown de um trecho do texto mostrado: os anexos entram como a linha de que vieram.
    func markdown(of range: NSRange) -> String {
        let mapping = currentMapping()
        guard range.location != NSNotFound, range.location + range.length < mapping.offsets.count else { return "" }
        let units = Array(mapping.markdown.utf16)
        return String(decoding: units[mapping.offsets[range.location]..<mapping.offsets[range.location + range.length]], as: UTF16.self)
    }

    /// Verdadeiro se o trecho do texto mostrado tem algum anexo.
    func containsAttachment(in range: NSRange) -> Bool {
        !attachmentRanges(in: range).isEmpty
    }

    /// Os trechos de `enclosing` que são anexos, para as Ferramentas de Escrita não os reescreverem.
    func attachmentRanges(in enclosing: NSRange) -> [NSValue] {
        guard let storage = textView?.textStorage else { return [] }
        let bounded = NSIntersectionRange(enclosing, NSRange(location: 0, length: storage.length))
        var found: [NSValue] = []
        storage.enumerateAttribute(.attachment, in: bounded) { value, range, _ in
            if value is EmbeddedTextAttachment { found.append(NSValue(range: range)) }
        }
        return found
    }

    // MARK: Edição

    /// Troca tudo pelo Markdown dado, sem registrar o desfazer (o documento mudou por fora: limpar, abrir).
    func reload(_ markdown: String) {
        guard let textView, let storage = textView.textStorage else { return }
        if markdown.isEmpty { pictures = [:] }
        storage.setAttributedString(render(markdown, attributes: textView.typingAttributes))
        textView.undoManager?.removeAllActions()
    }

    /// Troca o texto pelo Markdown dado mexendo só no trecho que mudou, pelo caminho que registra o desfazer.
    func replaceMarkdown(with markdown: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let new = render(markdown, attributes: textView.typingAttributes)
        var table: [String: Int] = [:]
        let old = Self.units(of: storage, table: &table)
        let next = Self.units(of: new, table: &table)
        var prefix = 0
        while prefix < old.count, prefix < next.count, old[prefix] == next[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < next.count - prefix,
            old[old.count - 1 - suffix] == next[next.count - 1 - suffix]
        {
            suffix += 1
        }
        let range = NSRange(location: prefix, length: old.count - prefix - suffix)
        let replacement = new.attributedSubstring(from: NSRange(location: prefix, length: next.count - prefix - suffix))
        replace(range, with: replacement, in: textView)
    }

    /// Põe o texto no lugar da seleção, desfazível, e deixa o cursor depois dele.
    func replaceSelection(withMarkdown fragment: String) {
        guard let textView else { return }
        let rendered = render(fragment, attributes: textView.typingAttributes)
        let selected = textView.selectedRange()
        replace(selected, with: rendered, in: textView)
        textView.setSelectedRange(NSRange(location: selected.location + rendered.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Insere as linhas de bloco no cursor (no lugar da seleção), cada uma num bloco próprio, separadas do texto vizinho por uma
    /// linha em branco (`NoteImageMarkup.insertion`). Sem nada depois, deixa uma linha livre para o cursor continuar (`EditorCaret`).
    func insertBlocks(_ lines: [String]) {
        guard let textView else { return }
        let mapping = currentMapping()
        let selected = textView.selectedRange()
        let units = Array(mapping.markdown.utf16)
        let before = String(decoding: units[..<mapping.offsets[selected.location]], as: UTF16.self)
        let after = String(decoding: units[mapping.offsets[selected.location + selected.length]...], as: UTF16.self)
        let insertion = NoteImageMarkup.insertion(of: lines, after: before[...], before: after[...])
        replaceSelection(withMarkdown: after.isEmpty ? insertion + "\n" : insertion)
    }

    /// ⌫ no começo da linha logo abaixo de um anexo apaga o anexo, desfazível (`EditorCaret.rangeDeletedBackward`).
    /// - Returns: `true` se apagou; `false` deixa o ⌫ com o campo.
    func deleteAttachmentBackward() -> Bool {
        deleteAttachment { EditorCaret.rangeDeletedBackward(from: $0, in: $1) }
    }

    /// Delete no fim da linha logo acima de um anexo apaga o anexo, desfazível (`EditorCaret.rangeDeletedForward`).
    /// - Returns: `true` se apagou; `false` deixa o Delete com o campo.
    func deleteAttachmentForward() -> Bool {
        deleteAttachment { EditorCaret.rangeDeletedForward(from: $0, in: $1) }
    }

    /// Escolhe no campo o trecho do Markdown (em unidades UTF-16); uma ponta dentro de um anexo vai para depois dele.
    func select(markdownRange: Range<Int>) {
        guard let textView else { return }
        let offsets = currentMapping().offsets
        func location(_ offset: Int) -> Int { offsets.firstIndex { $0 >= offset } ?? offsets.count - 1 }
        let lower = location(markdownRange.lowerBound)
        let upper = max(lower, location(markdownRange.upperBound))
        textView.setSelectedRange(NSRange(location: lower, length: upper - lower))
    }

    // MARK: Interno

    private func attachment(for line: String, content: EmbeddedTextAttachment.Content) -> EmbeddedTextAttachment {
        let picture = pictures[line] ?? EditorAttachmentPicture.make(for: content)
        pictures[line] = picture
        return EmbeddedTextAttachment(markdownLine: line, content: content, picture: picture)
    }

    private func deleteAttachment(in range: (_ location: Int, _ text: NSString) -> NSRange?) -> Bool {
        guard let textView else { return false }
        let selected = textView.selectedRange()
        guard selected.length == 0, let target = range(selected.location, textView.string as NSString) else { return false }
        replace(target, with: NSAttributedString(), in: textView)
        return true
    }

    private func replace(_ range: NSRange, with attributed: NSAttributedString, in textView: NSTextView) {
        guard textView.shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: attributed)
        textView.didChangeText()
    }

    /// Uma unidade por caractere do texto mostrado, para achar o trecho que mudou: o texto vale por si; um anexo vale pela linha
    /// que guarda, e a mesma linha tem sempre o mesmo número (`table`, compartilhada entre as duas listas comparadas), então dois
    /// anexos de cartões diferentes nunca se confundem.
    private static func units(of attributed: NSAttributedString, table: inout [String: Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(attributed.length)
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let attachment = value as? EmbeddedTextAttachment {
                let line = attachment.markdownLine
                let number = table[line] ?? (0x1_0000 + table.count)
                table[line] = number
                result += Array(repeating: number, count: range.length)
            } else {
                result += (attributed.string as NSString).substring(with: range).utf16.map { Int($0) }
            }
        }
        return result
    }
}
