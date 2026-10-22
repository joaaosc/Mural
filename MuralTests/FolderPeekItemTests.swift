import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Leque da pasta")
@MainActor
struct FolderPeekItemTests {
    private let fileURL = { (item: BoardItem) -> URL? in
        URL(fileURLWithPath: "/tmp/\(item.id.uuidString)")
    }

    private func children(_ kinds: [ItemKind]) -> [BoardItem] {
        kinds.enumerated().map { index, kind in
            BoardItem(
                kind: kind, title: "Cartão \(index)", createdAt: Date(timeIntervalSince1970: Double(index)),
                stickyColor: kind == .sticky ? .pink : nil)
        }
    }

    @Test("Mostra os três mais recentes, do mais antigo ao mais novo")
    func latestThreeInCreationOrder() {
        let items = children([.text, .image, .sticky, .checklist, .pdf])
        let peeks = FolderPeekItem.latest(items, fileURL: fileURL)
        #expect(peeks.map(\.id) == items.suffix(3).map(\.id))
        #expect(peeks.last?.id == items.last?.id, "o mais novo fica por último, na frente")
    }

    @Test("Respeita o limite, inclusive zero, e pasta com menos cartões")
    func respectsLimit() {
        let items = children([.text, .image])
        #expect(FolderPeekItem.latest(items, limit: 1, fileURL: fileURL).map(\.id) == [items[1].id])
        #expect(FolderPeekItem.latest(items, limit: 0, fileURL: fileURL).isEmpty)
        #expect(FolderPeekItem.latest(items, fileURL: fileURL).map(\.id) == items.map(\.id))
        #expect(FolderPeekItem.latest([], fileURL: fileURL).isEmpty)
    }

    @Test("Só foto, vídeo e PDF levam o arquivo; o post-it leva a cor")
    func fileOnlyForStoredKinds() {
        let items = children([.image, .video, .pdf, .text, .checklist, .sticky, .folder])
        let peeks = FolderPeekItem.latest(items, limit: items.count, fileURL: fileURL)
        for (item, peek) in zip(items, peeks) {
            #expect((peek.fileURL != nil) == item.kind.storesFile, "\(item.kind)")
            #expect(peek.kind == item.kind)
            #expect(peek.title == item.title)
        }
        #expect(peeks.first { $0.kind == .sticky }?.stickyColor == .pink)
    }
}
