import Foundation

/// Lê o que o app Música entrega na área de transferência ao arrastar ou copiar.
///
/// Os formatos não são documentados; foram observados no Música 1.7.2 do macOS 27.2 e podem mudar.
/// Por isso a leitura é defensiva: os tipos são conferidos e o que não bate é ignorado, sem travar.
public enum AppleMusicPasteboardPayload {
    /// Máximo de itens devolvidos por leitura.
    static let maxSnapshots = 200

    // MARK: com.apple.musicui.genericmusicitem

    /// JSON no formato da API do Apple Music: um objeto ou uma lista de objetos.
    public static func snapshots(fromGenericItemJSON data: Data) -> [MusicSnapshot] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let objects: [Any]
        if let list = root as? [Any] {
            objects = list
        } else {
            objects = [root]
        }
        var result: [MusicSnapshot] = []
        for case let object as [String: Any] in objects {
            if let snapshot = snapshot(fromAPIObject: object) {
                result.append(snapshot)
                if result.count >= maxSnapshots { break }
            }
        }
        return result
    }

    private static func snapshot(fromAPIObject object: [String: Any]) -> MusicSnapshot? {
        guard var type = object["type"] as? String else { return nil }
        var isLibrary = false
        if type.hasPrefix("library-") {
            isLibrary = true
            type.removeFirst("library-".count)
        }
        let kind: MusicItemKind
        switch type {
        case "albums": kind = .album
        case "songs": kind = .song
        case "playlists": kind = .playlist
        case "stations": kind = .station
        default: return nil
        }
        let attributes = object["attributes"] as? [String: Any] ?? [:]
        guard let title = trimmed(attributes["name"]) else { return nil }

        var snapshot = MusicSnapshot(kind: kind, title: title)
        let playParams = attributes["playParams"] as? [String: Any]
        snapshot.catalogID = text(playParams?["catalogId"]) ?? (isLibrary ? nil : text(object["id"]))
        snapshot.storefront = storefront(fromHref: object["href"] as? String)

        if let address = attributes["url"] as? String, let url = URL(string: address),
            let link = AppleMusicLink.snapshot(from: url)
        {
            snapshot.url = link.url
            if snapshot.catalogID == nil {
                snapshot.kind = link.kind
                snapshot.catalogID = link.catalogID
                snapshot.storefront = snapshot.storefront ?? link.storefront
            }
        }
        if kind == .playlist, isLibrary, snapshot.catalogID == nil {
            snapshot.libraryPlaylistName = title
        }

        snapshot.subtitle = trimmed(attributes["artistName"]) ?? trimmed(attributes["curatorName"])
        snapshot.albumTitle = trimmed(attributes["albumName"])
        if let artwork = attributes["artwork"] as? [String: Any] {
            if let template = artwork["url"] as? String, template.contains("{w}") {
                snapshot.artworkTemplate = template
            }
            snapshot.backgroundHex = MusicSnapshot.normalizedHex(artwork["bgColor"] as? String)
            snapshot.primaryTextHex = MusicSnapshot.normalizedHex(artwork["textColor1"] as? String)
            snapshot.secondaryTextHex = MusicSnapshot.normalizedHex(artwork["textColor2"] as? String)
        }
        snapshot.trackCount = integer(attributes["trackCount"])
        snapshot.releaseDate = trimmed(attributes["releaseDate"])
        if let millis = double(attributes["durationInMillis"]) { snapshot.duration = millis / 1000 }
        return snapshot
    }

    /// `/v1/catalog/<loja>/…` -> `<loja>`.
    private static func storefront(fromHref href: String?) -> String? {
        guard let href else { return nil }
        let parts = href.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "catalog", !parts[2].isEmpty else { return nil }
        return parts[2].lowercased()
    }

    // MARK: com.apple.tv.metadata

    /// Lista de propriedades no formato da biblioteca do iTunes (`Tracks`, `Playlists`).
    public static func snapshots(fromTrackMetadata plist: Any) -> [MusicSnapshot] {
        guard let root = plist as? [String: Any], let tracks = root["Tracks"] as? [String: Any] else { return [] }

        var ordered: [String] = []
        var seen = Set<String>()
        if let playlists = root["Playlists"] as? [Any], let first = playlists.first as? [String: Any],
            let items = first["Playlist Items"] as? [Any]
        {
            for case let item as [String: Any] in items {
                guard let id = text(item["Track ID"]), tracks[id] is [String: Any], seen.insert(id).inserted
                else { continue }
                ordered.append(id)
            }
        }
        let remaining = tracks.compactMap { key, value -> (String, [String: Any])? in
            guard !seen.contains(key), let track = value as? [String: Any] else { return nil }
            return (key, track)
        }.sorted { lhs, rhs in
            let l = (integer(lhs.1["Disc Number"]) ?? 0, integer(lhs.1["Track Number"]) ?? 0, Int(lhs.0) ?? 0)
            let r = (integer(rhs.1["Disc Number"]) ?? 0, integer(rhs.1["Track Number"]) ?? 0, Int(rhs.0) ?? 0)
            if l != r { return l < r }
            return lhs.0 < rhs.0
        }
        ordered.append(contentsOf: remaining.map(\.0))

        var result: [MusicSnapshot] = []
        for id in ordered {
            guard let track = tracks[id] as? [String: Any], let snapshot = snapshot(fromTrack: track) else { continue }
            result.append(snapshot)
            if result.count >= maxSnapshots { break }
        }
        return result
    }

    private static func snapshot(fromTrack track: [String: Any]) -> MusicSnapshot? {
        guard let name = trimmed(track["Name"]) else { return nil }
        var snapshot = MusicSnapshot(kind: .song, title: name)
        if let address = track["Store URL"] as? String, let url = URL(string: address),
            let link = AppleMusicLink.snapshot(from: url, title: name)
        {
            snapshot.kind = link.kind
            snapshot.catalogID = link.catalogID
            snapshot.url = link.url
        }
        snapshot.subtitle = trimmed(track["Artist"])
        snapshot.albumTitle = trimmed(track["Album"])
        if let millis = double(track["Total Time"]) { snapshot.duration = millis / 1000 }
        if let date = track["Release Date"] as? Date { snapshot.releaseDate = isoDay(date) }
        return snapshot
    }

    private static func isoDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: com.apple.music.playlist.name

    /// Arrastar uma playlist própria traz só o nome.
    public static func snapshot(fromPlaylistName name: String) -> MusicSnapshot? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return MusicSnapshot(kind: .playlist, libraryPlaylistName: name, title: name)
    }

    // MARK: Leitura de tipos

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let result = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Texto ou número (inteiro) como texto; booleanos e fracionários não valem.
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return trimmed(string) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            if let int = integer(number) { return String(int) }
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite && result >= 0 ? result : nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let result = double(value), result == result.rounded(), result < 9e15 else { return nil }
        return Int(result)
    }
}
