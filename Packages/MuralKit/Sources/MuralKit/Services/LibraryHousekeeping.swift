import Foundation

/// Quais cópias de segurança de um mural continuam na pasta `Backups/`. Os nomes são `<uuid>-<carimbo>.mural`, com o carimbo em UTC
/// (`20261030T120000Z`), então a ordem alfabética do carimbo é a ordem do tempo.
public enum BackupRetention {
    /// Quantas cópias mais novas de cada mural ficam.
    public static let keptPerBoard = 3

    /// O mural e o carimbo de um nome de cópia; `nil` para qualquer nome fora do padrão (esses nunca são tocados).
    static func parse(_ name: String) -> (board: UUID, stamp: String)? {
        let suffix = ".mural"
        guard name.hasSuffix(suffix) else { return nil }
        let stem = name.dropLast(suffix.count)
        // 36 do UUID, um hífen e 16 do carimbo.
        guard stem.count == 36 + 1 + 16 else { return nil }
        let id = stem.prefix(36)
        let rest = stem.dropFirst(36)
        guard rest.first == "-", let board = UUID(uuidString: String(id)) else { return nil }
        let stamp = Array(rest.dropFirst())
        let isStamp = stamp.indices.allSatisfy { index in
            switch index {
            case 8: stamp[index] == "T"
            case 15: stamp[index] == "Z"
            default: stamp[index].isASCII && stamp[index].isNumber
            }
        }
        return isStamp ? (board, String(stamp)) : nil
    }

    /// As cópias de `board` além das `keeping` mais novas, da mais antiga para a mais nova.
    public static func obsolete(names: [String], board: BoardID, keeping: Int = keptPerBoard) -> [String] {
        let own = names.compactMap { name in
            parse(name).flatMap { $0.board == board.rawValue ? (name: name, stamp: $0.stamp) : nil }
        }.sorted { $0.stamp < $1.stamp }
        return own.dropLast(max(keeping, 0)).map(\.name)
    }

    /// Todas as cópias de `board`: o mural foi excluído pela pessoa.
    public static func all(names: [String], board: BoardID) -> [String] {
        obsolete(names: names, board: board, keeping: 0)
    }

    /// Manda para o descarte as cópias antigas de `board` em `directory`, mantendo as `keeping` mais novas. Erro em uma cópia não
    /// impede as outras; pasta ausente não é erro.
    static func prune(
        _ board: BoardID, in directory: URL, keeping: Int, discard: (URL) throws -> Void
    ) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in obsolete(names: names, board: board, keeping: keeping) {
            try? discard(directory.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Manda para o Lixo todas as cópias de segurança de `board`.
    public static func discardAll(of board: BoardID, in directory: URL, discard: (URL) throws -> Void = BoardLibrary.moveToTrash) {
        prune(board, in: directory, keeping: 0, discard: discard)
    }
}

/// Pastas de `LinkPreviews/` que sobraram de murais que não existem mais.
public enum OrphanPreviews {
    /// Idade mínima da pasta: protege um mural sendo criado agora e outra cópia do app aberta.
    public static let minimumAge: TimeInterval = 24 * 60 * 60

    /// Nomes das pastas a apagar: UUID que não está em `keeping` e com mais de `minimumAge`. Nome que não é UUID, ou sem data de
    /// modificação, fica.
    public static func staleFolders(
        _ folders: [(name: String, modified: Date?)], keeping: Set<UUID>, now: Date = .now, minimumAge: TimeInterval = minimumAge
    ) -> [String] {
        folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.name), !keeping.contains(id), let modified = folder.modified,
                now.timeIntervalSince(modified) > minimumAge
            else { return nil }
            return folder.name
        }
    }

    /// Lê `directory` e manda para `discard` (por padrão, apaga de vez: são só caches refazíveis) as pastas órfãs.
    public static func clean(
        in directory: URL, keeping: Set<UUID>, now: Date = .now,
        discard: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }
        let folders = urls.compactMap { url -> (name: String, modified: Date?)? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { return nil }
            return (url.lastPathComponent, values?.contentModificationDate)
        }
        for name in staleFolders(folders, keeping: keeping, now: now) {
            try? discard(directory.appendingPathComponent(name, isDirectory: true))
        }
    }
}
