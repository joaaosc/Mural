import AppKit
import Foundation
import MuralKit

/// Monta o texto formatado (com as imagens coladas) que vai ao painel de compartilhar do Notas.
enum NotesRichText {
    private static let baseSize: CGFloat = 13
    private static let indentStep: CGFloat = 18

    static func attributedString(
        for blocks: [NoteExport.Block],
        imageURL: (String) -> URL?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(piece(for: block, imageURL: imageURL))
        }
        return result
    }

    private static func piece(for block: NoteExport.Block, imageURL: (String) -> URL?) -> NSAttributedString {
        switch block {
        case .title(let text):
            return plain(text, font: .systemFont(ofSize: 22, weight: .bold))
        case .heading(let level, let text):
            let size: CGFloat = [1: 19, 2: 17, 3: 15][level] ?? baseSize
            return plain(text, font: .systemFont(ofSize: size, weight: .bold))
        case .paragraph(let text):
            return inline(text)
        case .listItem(let marker, let depth, let text):
            return listItem(marker: marker, depth: depth, text: text)
        case .quote(let text):
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = indentStep
            style.headIndent = indentStep
            return inline(text, italic: true, style: style)
        case .code(let text):
            return plain(text, font: .monospacedSystemFont(ofSize: baseSize, weight: .regular))
        case .image(let fileName, let alt):
            if let url = imageURL(fileName), let image = NSImage(contentsOf: url) {
                let attachment = NSTextAttachment()
                attachment.image = image
                return NSAttributedString(attachment: attachment)
            }
            return plain(alt, font: .systemFont(ofSize: baseSize))
        case .rule:
            return plain(String(repeating: "—", count: 20), font: .systemFont(ofSize: baseSize))
        }
    }

    private static func listItem(marker: NoteExport.Marker, depth: Int, text: String) -> NSAttributedString {
        let prefix: String =
            switch marker {
            case .bullet: "• "
            case .ordered(let number): "\(number). "
            case .task(let done): done ? "☑ " : "☐ "
            }
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(depth) * indentStep
        style.firstLineHeadIndent = indent
        style.headIndent = indent + indentStep
        let result = NSMutableAttributedString(string: prefix, attributes: [.font: NSFont.systemFont(ofSize: baseSize)])
        result.append(inline(text))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func plain(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font])
    }

    /// Interpreta a marcação em linha: negrito, itálico, código e link.
    private static func inline(
        _ text: String,
        italic: Bool = false,
        style: NSParagraphStyle? = nil
    ) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: baseSize)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return plain(text, font: base)
        }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = base
            if intent.contains(.code) { font = .monospacedSystemFont(ofSize: baseSize, weight: .regular) }
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) || italic { traits.insert(.italicFontMask) }
            if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let link = run.link { attributes[.link] = link }
            if let style { attributes[.paragraphStyle] = style }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}

/// Manda o texto de um cartão ao Notas pelo painel de compartilhar do próprio Notas. Sem esse serviço,
/// abre o menu Compartilhar. A instância se segura enquanto o compartilhamento está em andamento,
/// porque o serviço não guarda o delegado.
@MainActor
final class NotesSharing: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
    /// Nome do serviço do Notas; não é documentado, por isso há o menu Compartilhar de reserva.
    private static let serviceName = NSSharingService.Name("com.apple.Notes.SharingExtension")

    private weak var model: BoardModel?
    private var keepAlive: NotesSharing?

    func share(_ item: BoardItem, model: BoardModel, from view: NSView?) {
        let blocks = NoteExport.blocks(for: item)
        guard !blocks.isEmpty else { return }
        self.model = model
        let content = NotesRichText.attributedString(for: blocks) { model.noteImageURL(named: $0) }
        keepAlive = self
        if let service = NSSharingService(named: Self.serviceName), service.canPerform(withItems: [content]) {
            service.delegate = self
            service.perform(withItems: [content])
            return
        }
        guard let anchor = view ?? NSApp.keyWindow?.contentView else {
            keepAlive = nil
            return
        }
        let picker = NSSharingServicePicker(items: [content])
        picker.delegate = self
        let rect = view == nil ? NSRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 1, height: 1) : anchor.bounds
        picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        let nsError = error as NSError
        if !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) {
            model?.lastError = "Não foi possível salvar no Notas."
        }
        keepAlive = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        keepAlive = nil
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        if service == nil { keepAlive = nil }
    }
}
