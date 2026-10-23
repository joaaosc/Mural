import AppKit
import Foundation
import MuralKit
import UniformTypeIdentifiers

/// Um item do Apple Music lido da área de transferência, com a capa quando ela veio no arrasto.
struct MusicDraft: Equatable, Sendable {
    var snapshot: MusicSnapshot
    /// Capa já em imagem (TIFF), quando veio junto; as demais saem do endereço do molde.
    var artworkData: Data?
}

/// Lê o que o app Música entrega ao arrastar ou copiar: álbum, faixa, playlist ou estação.
///
/// Os formatos não são documentados; foram observados no Música 1.7.2 do macOS 27.2. A leitura é defensiva:
/// o que não bate é ignorado, sem travar.
enum MusicPasteboardReader {
    static let genericItemType = NSPasteboard.PasteboardType("com.apple.musicui.genericmusicitem")
    static let trackMetadataType = NSPasteboard.PasteboardType("com.apple.tv.metadata")
    static let playlistNameType = NSPasteboard.PasteboardType("com.apple.music.playlist.name")
    static let mediaItemPreviewType = NSPasteboard.PasteboardType("com.apple.amp.mediaItemPreview")

    /// Tipos de dados que o mural aceita ao soltar (a prévia só traz a capa).
    static let dropTypeIdentifiers: [String] = [genericItemType, trackMetadataType, playlistNameType].map(\.rawValue)

    /// Tipos que habilitam Colar mesmo quando o Música não oferece texto ou endereço junto.
    static let pasteTypes = dropTypeIdentifiers.map { UTType(importedAs: $0) }

    /// Máximo de itens devolvidos por leitura.
    private static let maxDrafts = 200
    /// Maior arquivo de prévia que se tenta decodificar.
    private nonisolated static let maxArchiveBytes = 32 * 1024 * 1024

    /// Algum item tem um tipo do Música (só olha os tipos, sem ler dados) ou os links copiados são todos do Apple Music.
    static func containsMusic(_ pasteboard: NSPasteboard) -> Bool {
        let musicTypes: Set<NSPasteboard.PasteboardType> = [genericItemType, trackMetadataType, playlistNameType]
        for item in pasteboard.pasteboardItems ?? [] where !musicTypes.isDisjoint(with: item.types) {
            return true
        }
        return !drafts(from: pasteboard).isEmpty
    }

    /// Os itens do Música da área de transferência, sem repetir (`dedupeKey`), na ordem da primeira ocorrência.
    /// Sem tipos do Música, vale uma lista de links só se todos forem do Apple Music; com algum link comum, devolve vazio.
    static func drafts(from pasteboard: NSPasteboard) -> [MusicDraft] {
        var found: [MusicDraft] = []
        var hasMusicType = false
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: genericItemType) {
                hasMusicType = true
                found += AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: data).map { MusicDraft(snapshot: $0) }
            } else if let data = item.data(forType: trackMetadataType) {
                hasMusicType = true
                guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                else { continue }
                let snapshots = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: plist)
                var artwork: Data?
                if snapshots.count == 1, let archive = item.data(forType: mediaItemPreviewType) {
                    artwork = artworkData(fromPreviewArchive: archive)
                }
                found += snapshots.map { MusicDraft(snapshot: $0, artworkData: artwork) }
            } else if let name = item.string(forType: playlistNameType),
                let snapshot = AppleMusicPasteboardPayload.snapshot(fromPlaylistName: name)
            {
                hasMusicType = true
                found.append(MusicDraft(snapshot: snapshot))
            }
        }
        if !hasMusicType { found = linkDrafts(from: pasteboard) }

        var seen = Set<String>()
        var result: [MusicDraft] = []
        for draft in found where seen.insert(draft.snapshot.dedupeKey).inserted {
            result.append(draft)
            if result.count >= maxDrafts { break }
        }
        return result
    }

    private static func linkDrafts(from pasteboard: NSPasteboard) -> [MusicDraft] {
        let links = LinkPasteboardReader.drafts(from: pasteboard)
        guard !links.isEmpty else { return [] }
        var result: [MusicDraft] = []
        for link in links {
            guard let snapshot = AppleMusicLink.snapshot(from: link.url, title: link.title) else { return [] }
            result.append(MusicDraft(snapshot: snapshot))
        }
        return result
    }

    /// A capa (TIFF) do arquivo `com.apple.amp.mediaItemPreview`, um `NSKeyedArchiver` cuja raiz é da classe
    /// `AMPMediaItemPreviewMetadata`. Recusa arquivos acima de 32 MB; qualquer falha devolve `nil`.
    nonisolated static func artworkData(fromPreviewArchive data: Data) -> Data? {
        guard data.count <= maxArchiveBytes,
            let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        unarchiver.requiresSecureCoding = true
        unarchiver.setClass(PreviewArtworkReader.self, forClassName: "AMPMediaItemPreviewMetadata")
        defer { unarchiver.finishDecoding() }
        let root = unarchiver.decodeObject(of: PreviewArtworkReader.self, forKey: NSKeyedArchiveRootObjectKey)
        return root?.artwork?.tiffRepresentation
    }
}

/// Lê só a capa do arquivo de prévia do Música; o resto das chaves é ignorado.
@objc(MLPreviewArtworkReader)
private nonisolated final class PreviewArtworkReader: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let artwork: NSImage?

    init?(coder: NSCoder) {
        artwork = coder.decodeObject(of: NSImage.self, forKey: "artwork")
        super.init()
    }

    func encode(with coder: NSCoder) {}
}
