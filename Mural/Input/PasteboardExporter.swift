import AppKit
import MuralKit

/// Copia um cartão para a área de transferência: o arquivo guardado, o endereço de um link (com o
/// título do cartão) ou, para notas e listas, o texto (no formato que o próprio mural reconhece ao colar).
enum PasteboardExporter {
    /// Nome da página que acompanha o endereço (`public.url`), como o Safari o grava ao copiar um link.
    private static let urlNameType = NSPasteboard.PasteboardType("public.url-name")

    static func copy(_ item: BoardItem, from model: BoardModel, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if item.kind == .link, let link = item.link {
            let address = link.url.absoluteString
            let entry = NSPasteboardItem()
            entry.setString(address, forType: .URL)
            entry.setString(item.title, forType: urlNameType)
            entry.setString(address, forType: .string)
            pasteboard.writeObjects([entry])
        } else if item.kind == .reminder, let reminder = item.reminder {
            pasteboard.setString(text(of: reminder), forType: .string)
        } else if let url = model.fileURL(for: item) {
            pasteboard.writeObjects([url as NSURL])
        } else if let checklist = item.checklist {
            pasteboard.setString(ChecklistParser.format(checklist), forType: .string)
        } else if item.kind == .text {
            pasteboard.setString(markdown(of: item), forType: .string)
        } else {
            pasteboard.setString(item.displayText, forType: .string)
        }
    }

    /// Título do lembrete e, se houver, a data, uma por linha.
    static func text(of reminder: ReminderSnapshot) -> String {
        [reminder.title, reminder.dueDescription()?.text].compactMap { $0 }.joined(separator: "\n")
    }

    /// Nota em Markdown com o título como `#`, no formato que o colar lê de volta.
    static func markdown(of item: BoardItem) -> String {
        let body = item.text ?? ""
        guard !item.title.isEmpty, ItemImporter.leadingHeading(of: body) == nil, !body.hasPrefix(item.title) else { return body }
        return body.isEmpty ? "# \(item.title)" : "# \(item.title)\n\n\(body)"
    }
}
