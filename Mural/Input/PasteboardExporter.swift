import AppKit
import MuralKit

/// Copia um cartão para a área de transferência: o arquivo guardado ou, para notas e
/// listas, o texto (listas no formato que o próprio mural reconhece ao colar).
enum PasteboardExporter {
    static func copy(_ item: BoardItem, from model: BoardModel, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if let url = model.fileURL(for: item) {
            pasteboard.writeObjects([url as NSURL])
        } else if let checklist = item.checklist {
            pasteboard.setString(ChecklistParser.format(checklist), forType: .string)
        } else {
            pasteboard.setString(item.displayText, forType: .string)
        }
    }
}
