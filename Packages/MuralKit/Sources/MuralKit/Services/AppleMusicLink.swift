import Foundation

/// Lê endereços do Apple Music (`music.apple.com`, `music://`, `itmss://itunes.com/album?…`)
/// e devolve o item que eles apontam. Só aceita álbum, faixa, playlist e estação do catálogo.
public enum AppleMusicLink {
    private static let schemes: Set<String> = ["http", "https", "music", "itms", "itmss"]
    private static let pathHosts: Set<String> = [
        "music.apple.com", "geo.music.apple.com", "embed.music.apple.com", "beta.music.apple.com",
    ]
    private static let legacyHosts: Set<String> = ["itunes.com", "itunes.apple.com"]

    public static func snapshot(from url: URL, title: String? = nil) -> MusicSnapshot? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else { return nil }
        if pathHosts.contains(host) {
            return pathSnapshot(components, scheme: scheme, title: title)
        }
        if legacyHosts.contains(host) {
            return legacySnapshot(components, title: title)
        }
        return nil
    }

    // MARK: Forma de caminho

    private static func pathSnapshot(_ source: URLComponents, scheme: String, title: String?) -> MusicSnapshot? {
        var parts = source.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var storefront: String?
        if let first = parts.first, first.utf8.count == 2, first.allSatisfy({ $0.isASCII && $0.isLetter }) {
            storefront = first.lowercased()
            parts.removeFirst()
        }
        guard let type = parts.first?.lowercased() else { return nil }
        let rest = Array(parts.dropFirst())
        guard rest.count == 1 || rest.count == 2, let id = rest.last else { return nil }
        let name = rest.count == 2 ? rest[0] : nil
        let items = source.queryItems ?? []

        let kind: MusicItemKind
        var catalogID = id
        switch type {
        case "album":
            guard isDigits(id) else { return nil }
            if let song = items.first(where: { $0.name == "i" })?.value, isDigits(song) {
                kind = .song
                catalogID = song
            } else {
                kind = .album
            }
        case "song":
            guard isDigits(id) else { return nil }
            kind = .song
        case "playlist":
            guard isOpaqueID(id, prefix: "pl.") else { return nil }
            kind = .playlist
        case "station":
            guard isOpaqueID(id, prefix: "ra.") else { return nil }
            kind = .station
        default:
            return nil
        }

        var clean = source
        if !["http", "https"].contains(scheme) { clean.scheme = "https" }
        let kept = (clean.percentEncodedQueryItems ?? []).filter { $0.name != "l" }
        clean.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        clean.fragment = nil

        return MusicSnapshot(
            kind: kind, catalogID: catalogID, storefront: storefront, url: clean.url,
            title: resolvedTitle(title, pathName: name, kind: kind))
    }

    // MARK: Forma da loja antiga

    private static func legacySnapshot(_ source: URLComponents, title: String?) -> MusicSnapshot? {
        let parts = source.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1, parts[0].lowercased() == "album" else { return nil }
        let items = source.queryItems ?? []
        let album = items.first(where: { $0.name == "p" })?.value.flatMap { isDigits($0) ? $0 : nil }
        let song = items.first(where: { $0.name == "i" })?.value.flatMap { isDigits($0) ? $0 : nil }

        if let song {
            let address = album.map { "https://music.apple.com/album/\($0)?i=\(song)" }
                ?? "https://music.apple.com/song/\(song)"
            return MusicSnapshot(
                kind: .song, catalogID: song, url: URL(string: address),
                title: resolvedTitle(title, pathName: nil, kind: .song))
        }
        if let album {
            return MusicSnapshot(
                kind: .album, catalogID: album, url: URL(string: "https://music.apple.com/album/\(album)"),
                title: resolvedTitle(title, pathName: nil, kind: .album))
        }
        return nil
    }

    // MARK: Apoio

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    /// Id opaco com prefixo (`pl.`, `ra.`) e o resto só com letras, dígitos, ponto, hífen e sublinhado.
    private static func isOpaqueID(_ text: String, prefix: String) -> Bool {
        guard text.hasPrefix(prefix), text.count > prefix.count else { return false }
        return text.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
                || $0 == 0x2E || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func resolvedTitle(_ given: String?, pathName: String?, kind: MusicItemKind) -> String {
        if let given = given?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty { return given }
        if let pathName {
            let spaced = pathName.replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = spaced.first { return first.uppercased() + spaced.dropFirst() }
        }
        switch kind {
        case .album: return "Álbum"
        case .song: return "Música"
        case .playlist: return "Playlist"
        case .station: return "Estação"
        }
    }
}
