import CoreGraphics
import Foundation
import ImageIO

/// Ajusta um mural vindo de fora para que nada do que o pacote declara quebre a exibição ou toque em dados da pessoa.
/// Roda só na importação, depois da conferência do pacote e antes de gravar; o mural interno nunca passa por aqui.
enum BoardImportNormalizer {
    static let maximumFreeTexts = 10_000
    static let maximumCoordinate = 1_000_000.0
    static let maximumTextBytes = 4 * 1024 * 1024
    static let maximumTitleCharacters = 1_000
    static let maximumTagCharacters = 100
    static let maximumLinkAttempts = 64

    /// `itemsURL` é a pasta `Items/` da cópia em staging, de onde saem as dimensões e o tamanho reais das imagens.
    static func normalize(_ board: Board, itemsURL: URL) throws -> Board {
        guard board.freeTexts.count <= maximumFreeTexts else {
            throw BoardPortablePackageError.tooManyFreeTexts(limit: maximumFreeTexts)
        }
        var board = board
        for index in board.items.indices {
            try normalize(&board.items[index], itemsURL: itemsURL)
        }
        var seen = Set<UUID>()
        for index in board.freeTexts.indices {
            guard board.freeTexts[index].text.utf8.count <= maximumTextBytes else {
                throw BoardPortablePackageError.textTooLarge(board.freeTexts[index].id)
            }
            // O primeiro texto com o id o mantém; os repetidos ganham um novo, para não se confundirem na seleção e na edição.
            if !seen.insert(board.freeTexts[index].id).inserted {
                var fresh = UUID()
                while !seen.insert(fresh).inserted { fresh = UUID() }
                board.freeTexts[index].id = fresh
            }
            board.freeTexts[index].position = clamped(board.freeTexts[index].position)
        }
        return board
    }

    private static func normalize(_ item: inout BoardItem, itemsURL: URL) throws {
        try ensureTextsFit(item)
        item.position = clamped(item.position)
        item.folderPosition = item.folderPosition.map(clamped)
        if item.title.count > maximumTitleCharacters { item.title = String(item.title.prefix(maximumTitleCharacters)) }
        if let tag = item.tag, tag.count > maximumTagCharacters { item.tag = String(tag.prefix(maximumTagCharacters)) }

        if item.kind == .image, item.imageMetadata != nil, let fileName = item.fileName {
            item.imageMetadata = item.imageMetadata.flatMap { rereadMetadata($0, at: itemsURL.appendingPathComponent(fileName)) }
        }
        if let attachments = item.attachments {
            item.attachments = attachments.map { attachment in
                let size = pixelSize(of: itemsURL.appendingPathComponent(attachment.fileName))
                return NoteAttachment(
                    fileName: attachment.fileName,
                    pixelWidth: max(1, size?.width ?? 0),
                    pixelHeight: max(1, size?.height ?? 0))
            }
        }
        // O lembrete chega desligado do app Lembretes: sem identificador, nenhum arquivo consegue ler nem marcar um lembrete real.
        if var reminder = item.reminder {
            reminder.identifier = ""
            reminder.externalIdentifier = nil
            item.reminder = reminder
        }
        if var link = item.link, case .failed(let date, let attempts) = link.preview {
            link.preview = .failed(at: date, attempts: min(max(attempts, 0), maximumLinkAttempts))
            item.link = link
        }
    }

    /// Posição presa a ±1_000_000 em cada eixo. Só o que passa do limite muda: posições negativas e com fração são válidas
    /// (texto solto à esquerda da origem, post-it à esquerda do meio da pasta) e o mural interno as guarda assim.
    private static func clamped(_ point: BoardPoint) -> BoardPoint {
        func limit(_ value: Double) -> Double {
            value.isFinite ? min(max(value, -maximumCoordinate), maximumCoordinate) : 0
        }
        return BoardPoint(x: limit(point.x), y: limit(point.y))
    }

    /// Recusa o cartão se algum campo de texto passa de 4 MB; títulos e etiquetas longos só são cortados depois.
    private static func ensureTextsFit(_ item: BoardItem) throws {
        var texts: [String?] = [item.title, item.text, item.caption, item.tag]
        if let checklist = item.checklist {
            texts.append(checklist.title)
            texts.append(checklist.intro)
            for section in checklist.sections {
                texts.append(section.title)
                texts.append(contentsOf: section.entries.map(\.text))
            }
        }
        if let link = item.link {
            texts.append(contentsOf: [link.pageTitle, link.siteName, link.summary])
        }
        for case let text? in texts where text.utf8.count > maximumTextBytes {
            throw BoardPortablePackageError.textTooLarge(item.id)
        }
    }

    /// Dimensões e tamanho vêm do arquivo, não do pacote; sem cabeçalho legível, o cartão fica sem metadados.
    private static func rereadMetadata(_ declared: ImageMetadata, at url: URL) -> ImageMetadata? {
        guard let size = pixelSize(of: url), size.width > 0, size.height > 0 else { return nil }
        var metadata = declared
        metadata.pixelWidth = size.width
        metadata.pixelHeight = size.height
        metadata.fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        metadata.palette = Array(declared.palette.prefix(ImageInspector.defaultPaletteSize))
        return metadata
    }

    /// Lê só o cabeçalho, sem decodificar a imagem. Como o `ImageInspector`, não considera a orientação.
    private static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}
