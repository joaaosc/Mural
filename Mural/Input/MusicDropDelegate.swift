import AppKit
import SwiftUI

/// Lê os tipos privados que o app Música põe no pasteboard de arrasto e conserva o ponto real da soltura.
struct MusicDropDelegate: DropDelegate {
    let receive: ([MusicDraft], CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: MusicPasteboardReader.dropTypeIdentifiers)
    }

    func performDrop(info: DropInfo) -> Bool {
        let drafts = MusicPasteboardReader.drafts(from: NSPasteboard(name: .drag))
        return !drafts.isEmpty && receive(drafts, info.location)
    }
}
