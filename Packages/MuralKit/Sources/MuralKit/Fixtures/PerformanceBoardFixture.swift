import Foundation

/// Tamanhos padronizados do corpus estrutural usado nas medições de performance.
public enum PerformanceFixtureSize: Int, CaseIterable, Sendable {
    case items100 = 100
    case items500 = 500
    case items2000 = 2_000
}

/// Proporção de cartões de mídia (`image`, `video` e `pdf`) no corpus estrutural.
public enum PerformanceFixtureMediaDensity: Int, CaseIterable, Sendable {
    case percent10 = 10
    case percent50 = 50
    case percent90 = 90
}

/// Gera murais reprodutíveis para a primeira fase das medições de performance.
///
/// Esta é uma fixture estrutural: `fileName`, `previewImageFile` e `artworkFile` são
/// nomes determinísticos sem arquivos correspondentes, e nenhum byte de mídia é criado.
/// Portanto, o resultado mede estrutura, hierarquia, layout e metadados; não mede decode,
/// geração de thumbnail ou I/O de arquivos de mídia reais.
public enum PerformanceBoardFixture {
    private static let baseDate = Date(timeIntervalSince1970: 1_735_689_600)
    private static let nonMediaPrefixCount = 10

    /// Cria um mural com a quantidade e a densidade de mídia especificadas.
    ///
    /// A proporção é calculada sobre `Board.items.count`, sem arredondamento para os
    /// tamanhos públicos disponíveis. Como os três tamanhos são múltiplos de 10, a
    /// quantidade de mídia é sempre exata para as três densidades públicas.
    public static func make(
        size: PerformanceFixtureSize,
        mediaDensity: PerformanceFixtureMediaDensity
    ) -> Board {
        let itemCount = size.rawValue
        let mediaCount = itemCount * mediaDensity.rawValue / 100
        let folderIDs = (0..<3).map(id(for:))

        var items: [BoardItem] = []
        items.reserveCapacity(itemCount)
        for index in 0..<itemCount {
            items.append(
                makeItem(
                    index: index,
                    mediaCount: mediaCount,
                    folderIDs: folderIDs
                )
            )
        }
        return Board(items: items)
    }

    private static func makeItem(
        index: Int,
        mediaCount: Int,
        folderIDs: [UUID]
    ) -> BoardItem {
        let id = id(for: index)
        let createdAt = baseDate.addingTimeInterval(TimeInterval(index))
        let position = position(for: index)

        if index < nonMediaPrefixCount {
            return makeRequiredNonMediaItem(
                index: index,
                id: id,
                createdAt: createdAt,
                position: position,
                folderIDs: folderIDs
            )
        }

        if index < nonMediaPrefixCount + mediaCount {
            return makeMediaItem(
                index: index,
                mediaOrdinal: index - nonMediaPrefixCount,
                id: id,
                createdAt: createdAt,
                position: position,
                parentID: parentID(for: index, folderIDs: folderIDs)
            )
        }

        let nonMediaOrdinal = index - nonMediaPrefixCount - mediaCount
        return makeAdditionalNonMediaItem(
            index: index,
            nonMediaOrdinal: nonMediaOrdinal,
            id: id,
            createdAt: createdAt,
            position: position,
            parentID: parentID(for: index, folderIDs: folderIDs)
        )
    }

    /// Os dez primeiros cartões garantem a variedade mínima, inclusive dois estados de link.
    private static func makeRequiredNonMediaItem(
        index: Int,
        id: UUID,
        createdAt: Date,
        position: BoardPoint,
        folderIDs: [UUID]
    ) -> BoardItem {
        switch index {
        case 0:
            return BoardItem(
                id: id,
                kind: .folder,
                title: "Fixture Folder 1",
                createdAt: createdAt,
                position: position,
                tag: "FIXTURE"
            )
        case 1:
            return BoardItem(
                id: id,
                kind: .folder,
                title: "Fixture Folder 2",
                createdAt: createdAt,
                parentID: folderIDs[0],
                position: position,
                tag: "FIXTURE"
            )
        case 2:
            return BoardItem(
                id: id,
                kind: .folder,
                title: "Fixture Folder 3",
                createdAt: createdAt,
                parentID: folderIDs[1],
                position: position,
                tag: "FIXTURE"
            )
        case 3:
            return BoardItem(
                id: id,
                kind: .text,
                title: "Fixture Text",
                createdAt: createdAt,
                position: position,
                text: "Structural fixture text \(index).",
                caption: "Structural fixture"
            )
        case 4:
            return BoardItem(
                id: id,
                kind: .checklist,
                title: "Fixture Checklist",
                createdAt: createdAt,
                position: position,
                checklist: checklist(for: index)
            )
        case 5:
            return BoardItem(
                id: id,
                kind: .sticky,
                title: "Fixture Sticky",
                createdAt: createdAt,
                position: position,
                text: "Structural fixture sticky \(index).",
                stickyColor: .yellow
            )
        case 6:
            return BoardItem(
                id: id,
                kind: .link,
                title: "Fixture Link With Preview",
                createdAt: createdAt,
                position: position,
                link: link(for: index, hasPreview: true)
            )
        case 7:
            return BoardItem(
                id: id,
                kind: .link,
                title: "Fixture Link Without Preview",
                createdAt: createdAt,
                position: position,
                link: link(for: index, hasPreview: false)
            )
        case 8:
            return BoardItem(
                id: id,
                kind: .reminder,
                title: "Fixture Reminder",
                createdAt: createdAt,
                position: position,
                reminder: reminder(for: index, createdAt: createdAt)
            )
        case 9:
            return BoardItem(
                id: id,
                kind: .music,
                title: "Fixture Music",
                createdAt: createdAt,
                position: position,
                music: music(for: index)
            )
        default:
            preconditionFailure("invalid required fixture index")
        }
    }

    private static func makeMediaItem(
        index: Int,
        mediaOrdinal: Int,
        id: UUID,
        createdAt: Date,
        position: BoardPoint,
        parentID: UUID?
    ) -> BoardItem {
        let kind: ItemKind
        let fileExtension: String
        switch mediaOrdinal % 3 {
        case 0:
            kind = .image
            fileExtension = ["heic", "jpeg", "png"][(mediaOrdinal / 3) % 3]
        case 1:
            kind = .video
            fileExtension = ["mov", "mp4"][(mediaOrdinal / 3) % 2]
        default:
            kind = .pdf
            fileExtension = "pdf"
        }

        let item = BoardItem(
            id: id,
            kind: kind,
            title: "Fixture \(kind.rawValue.capitalized) \(index)",
            createdAt: createdAt,
            parentID: parentID,
            position: position,
            fileName: "structural-fixture-\(id.uuidString.lowercased()).\(fileExtension)"
        )
        if kind == .image {
            var image = item
            image.imageMetadata = ImageMetadata(
                pixelWidth: 1_600 + (index % 4) * 100,
                pixelHeight: 900 + (index % 3) * 100,
                fileSizeBytes: 1_024,
                colorProfile: "sRGB",
                palette: []
            )
            return image
        }
        return item
    }

    private static func makeAdditionalNonMediaItem(
        index: Int,
        nonMediaOrdinal: Int,
        id: UUID,
        createdAt: Date,
        position: BoardPoint,
        parentID: UUID?
    ) -> BoardItem {
        switch nonMediaOrdinal % 6 {
        case 0:
            let attachment = NoteAttachment(
                fileName: "structural-fixture-attachment-\(id.uuidString.lowercased()).png",
                pixelWidth: 800,
                pixelHeight: 600
            )
            return BoardItem(
                id: id,
                kind: .text,
                title: "Fixture Text \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                text: "Structural fixture text \(index) with an attachment reference.",
                attachments: [attachment]
            )
        case 1:
            return BoardItem(
                id: id,
                kind: .checklist,
                title: "Fixture Checklist \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                checklist: checklist(for: index)
            )
        case 2:
            let sticky = BoardItem(
                id: id,
                kind: .sticky,
                title: "Fixture Sticky \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                text: "Structural fixture sticky \(index).",
                stickyColor: StickyColor.allCases[index % StickyColor.allCases.count]
            )
            var placed = sticky
            if parentID != nil {
                placed.folderPosition = BoardPoint(x: Double(index % 11) * 18, y: Double(index % 7) * 24)
            }
            return placed
        case 3:
            return BoardItem(
                id: id,
                kind: .link,
                title: "Fixture Link \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                link: link(for: index, hasPreview: index.isMultiple(of: 2))
            )
        case 4:
            return BoardItem(
                id: id,
                kind: .reminder,
                title: "Fixture Reminder \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                reminder: reminder(for: index, createdAt: createdAt)
            )
        default:
            return BoardItem(
                id: id,
                kind: .music,
                title: "Fixture Music \(index)",
                createdAt: createdAt,
                parentID: parentID,
                position: position,
                music: music(for: index)
            )
        }
    }

    private static func parentID(for index: Int, folderIDs: [UUID]) -> UUID? {
        index.isMultiple(of: 5) ? nil : folderIDs[(index + 1) % folderIDs.count]
    }

    private static func position(for index: Int) -> BoardPoint {
        BoardPoint(
            x: 24 + Double(index % 25) * 152,
            y: 24 + Double(index / 25) * 136
        )
    }

    private static func id(for index: Int) -> UUID {
        let tail = String(index + 1, radix: 16)
        let paddedTail = String(repeating: "0", count: max(0, 12 - tail.count)) + tail
        return UUID(uuidString: "00000000-0000-4000-8000-\(paddedTail)")!
    }

    private static func checklist(for index: Int) -> ChecklistDocument {
        ChecklistDocument(
            title: "Fixture Checklist \(index)",
            intro: "Structural fixture checklist.",
            sections: [
                ChecklistSection(
                    id: id(for: 100_000 + index * 2),
                    title: "Fixture Section",
                    entries: [
                        ChecklistEntry(
                            id: id(for: 100_001 + index * 2),
                            text: "Fixture entry \(index)",
                            isDone: index.isMultiple(of: 2)
                        )
                    ]
                )
            ]
        )
    }

    private static func link(for index: Int, hasPreview: Bool) -> LinkInfo {
        let url = URL(string: "https://fixture.invalid/page-\(index)")!
        guard hasPreview else { return LinkInfo(url: url, preview: .pending) }
        let fetchedAt = baseDate.addingTimeInterval(TimeInterval(index) + 0.5)
        return LinkInfo(
            url: url,
            pageTitle: "Fixture page \(index)",
            siteName: "fixture.invalid",
            summary: "Structural link preview.",
            remoteImageURL: URL(string: "https://fixture.invalid/preview-\(index).jpg"),
            previewImageFile: "structural-fixture-preview-\(index).jpg",
            preview: .ready(fetchedAt: fetchedAt)
        )
    }

    private static func reminder(for index: Int, createdAt: Date) -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: "fixture-reminder-\(index)",
            externalIdentifier: "fixture-external-\(index)",
            title: "Fixture reminder \(index)",
            notes: "Structural reminder snapshot.",
            dueDate: createdAt.addingTimeInterval(86_400),
            dueHasTime: true,
            priority: index % 6,
            listTitle: "Fixture List",
            listColorHex: "#336699",
            url: URL(string: "x-apple-reminderkit://fixture/\(index)")
        )
    }

    private static func music(for index: Int) -> MusicSnapshot {
        MusicSnapshot(
            kind: [.album, .song, .playlist, .station][index % 4],
            catalogID: "fixture-catalog-\(index)",
            storefront: "br",
            url: URL(string: "https://music.apple.com/br/item/fixture-\(index)"),
            title: "Fixture music \(index)",
            subtitle: "Fixture artist",
            artworkTemplate: "https://fixture.invalid/artwork/{w}x{h}.{f}",
            artworkFile: "structural-fixture-artwork-\(index).jpg",
            backgroundHex: "#112233",
            primaryTextHex: "#ffffff",
            secondaryTextHex: "#dddddd",
            trackCount: index % 12,
            releaseDate: "2026-01-01",
            duration: 180
        )
    }
}
