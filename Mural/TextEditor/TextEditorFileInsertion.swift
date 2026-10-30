import Foundation
import ImageIO
import MuralKit
import UniformTypeIdentifiers

/// Lê os arquivos escolhidos no painel do Finder para o editor: imagens e contatos (`.vcf`), os únicos que entram num Card de texto.
///
/// Os bytes são lidos na hora, com o acesso de sandbox aberto só durante a leitura: a imagem fica na memória até ir para um mural, e
/// até lá o acesso ao arquivo já teria acabado. Um arquivo que não dá para ler (grande demais, danificado, de outro tipo que o painel
/// deixou passar) é contado em `failures`, e os outros seguem.
enum TextEditorFileInsertion {
    /// O que entra no editor, na ordem dos arquivos.
    enum Piece: Sendable {
        case image(NoteImagePaste.Source)
        case contacts([ContactDraft])
    }

    /// O que a leitura achou.
    struct Reading: Sendable {
        var pieces: [Piece] = []
        var failures = 0
    }

    /// Os tipos que o painel do Finder deixa escolher.
    static let allowedTypes: [UTType] = [.image, .vCard]
    /// Só contatos, para o item Contato… do menu.
    static let contactTypes: [UTType] = [.vCard]
    /// Maior arquivo que se tenta ler, em bytes: a imagem fica inteira na memória até ser colada num mural.
    nonisolated static let maximumBytes = 64 * 1024 * 1024

    static func read(_ urls: [URL]) async -> Reading {
        var reading = Reading()
        for url in urls {
            if let piece = piece(from: await load(url)) {
                reading.pieces.append(piece)
            } else {
                reading.failures += 1
            }
        }
        return reading
    }

    // MARK: Interno

    private struct LoadedFile: Sendable {
        let data: Data
        let fileExtension: String
        let isContact: Bool
    }

    /// Fora do ator principal: um arquivo que está só no iCloud leva o tempo de baixar.
    @concurrent
    private nonisolated static func load(_ url: URL) async -> LoadedFile? {
        let isOpen = url.startAccessingSecurityScopedResource()
        defer { if isOpen { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= maximumBytes, let data = try? Data(contentsOf: url) else { return nil }
        let fileExtension = url.pathExtension.lowercased()
        let isContact = UTType(filenameExtension: fileExtension)?.conforms(to: .vCard) ?? false
        guard isContact || isImage(data) else { return nil }
        return LoadedFile(data: data, fileExtension: fileExtension, isContact: isContact)
    }

    private nonisolated static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    private static func piece(from file: LoadedFile?) -> Piece? {
        guard let file else { return nil }
        guard file.isContact else { return .image(NoteImagePaste.source(data: file.data, fileExtension: file.fileExtension)) }
        let drafts = ContactVCardReader.drafts(fromVCard: file.data)
        return drafts.isEmpty ? nil : .contacts(drafts)
    }
}
