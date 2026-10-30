import Foundation

/// O que fazer na pasta do iCloud Drive para as cópias acompanharem os murais deste Mac: função pura da biblioteca, do que há na
/// pasta e do que este Mac anotou. Só os murais da própria pessoa têm cópia (só deste Mac, ou dela no iCloud); os recebidos de
/// outra pessoa nunca. A cópia só é regravada quando este Mac mudou o mural (`pendingWrites`) ou quando ela falta: o que chegou de
/// outro Mac pelo iCloud já foi copiado por ele. Só sai da pasta a cópia de um mural que a pessoa excluiu neste Mac (`pendingTrash`).
///
/// Quando a pessoa renomeia a cópia no Finder, o nome vale: o mural é renomeado no app (`renameBoard`) em vez de a cópia voltar ao
/// nome antigo. Isso só vale se o mural não mudou de nome no app desde a última cópia; senão, o nome do app prevalece.
///
/// As ações saem em ordem: todos os `trash`, depois os `renameBoard`, depois os `move`, depois os `write`; dentro de cada grupo,
/// pelo nome do arquivo (o de origem, nos `move`), exceto os `renameBoard`, que seguem a ordem dos murais.
public struct DriveMirrorPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Leva ao Lixo a cópia de um mural que a pessoa excluiu.
        case trash(BoardID, fileName: String)
        /// Renomeia o mural no app para o nome que a pessoa deu à cópia no Finder.
        case renameBoard(BoardID, to: String)
        /// Renomeia a cópia para o nome que o mural tem agora.
        case move(BoardID, from: String, to: String)
        /// Grava a cópia no pacote com esse nome (ver `BoardPackageMirror.sync`).
        case write(BoardID, fileName: String)
    }

    public var actions: [Action]

    public init(actions: [Action] = []) {
        self.actions = actions
    }

    /// - Parameters:
    ///   - boards: os manifestos dos murais salvos deste Mac.
    ///   - copies: o que há na pasta: nome do pacote (`*.mural`) → id do manifesto dele; `nil` quando ilegível ou não é mural.
    ///   - copyNames: nome do pacote → nome gravado no manifesto da cópia (o que o mural se chamava na última cópia).
    ///   - strays: pasta de primeiro nível sem `.mural` mas com manifesto legível → id do mural (pacote que perdeu a extensão).
    ///   - pendingWrites: murais gravados neste Mac desde a última cópia.
    ///   - pendingTrash: murais excluídos pela pessoa neste Mac.
    ///   - awaitingFirstFetch: murais adotados do iCloud que ainda esperam o conteúdo (pacote provisório).
    public static func make(
        boards: [BoardManifest], copies: [String: BoardID?], copyNames: [String: String] = [:], strays: [String: BoardID] = [:],
        pendingWrites: Set<BoardID>, pendingTrash: Set<BoardID>, awaitingFirstFetch: Set<BoardID>
    ) -> DriveMirrorPlan {
        // O que há na pasta, em ordem de nome (o dicionário não tem ordem).
        let folder = copies.map { FolderEntry(name: $0.key, boardID: $0.value) }.sorted { precedes($0.name, $1.name) }
        var occupants: [String: [BoardID?]] = [:]
        var namesByBoard: [BoardID: [String]] = [:]
        for entry in folder {
            occupants[nameKey(entry.name), default: []].append(entry.boardID)
            if let boardID = entry.boardID { namesByBoard[boardID, default: []].append(entry.name) }
        }

        // Os murais com cópia recebem nomes em ordem, para o mesmo nome sobrar sempre para o mesmo mural.
        var handedOut = Set<String>()
        var renames: [Rename] = []
        var boardRenames: [Action] = []
        var writes: [(boardID: BoardID, fileName: String)] = []
        let mirrored = boards.filter { hasCopy($0, awaitingFirstFetch: awaitingFirstFetch) }.sorted(by: boardOrder)

        // Pasta que perdeu a extensão: volta a ser pacote e o nome dela vira o do mural. O mural que já tem cópia `.mural` ignora a
        // pasta. Enquanto isso o mural não ganha cópia nova: a seguinte já encontra o pacote.
        var recovered = Set<BoardID>()
        for (folderName, boardID) in strays.sorted(by: { precedes($0.key, $1.key) }) {
            guard let board = mirrored.first(where: { $0.id == boardID }), namesByBoard[boardID] == nil,
                !recovered.contains(boardID)
            else { continue }
            recovered.insert(boardID)
            renames.append(Rename(boardID: boardID, from: folderName, to: folderName + packageExtension, writesAfterwards: false))
            let name = BoardName.sanitized(folderName)
            if name != board.name { boardRenames.append(.renameBoard(boardID, to: name)) }
        }

        for board in mirrored where !recovered.contains(board.id) {
            // Cópia renomeada no Finder: o mural ganha o nome novo, e a gravação dele traz a cópia de volta ao nome certo.
            if let name = finderRename(for: board, copies: namesByBoard[board.id] ?? [], copyNames: copyNames) {
                boardRenames.append(.renameBoard(board.id, to: name))
                continue
            }
            let wanted = desiredName(for: board, handedOut: handedOut, occupants: occupants)
            handedOut.insert(nameKey(wanted))
            let isPending = pendingWrites.contains(board.id)
            let own = namesByBoard[board.id] ?? []
            // Com mais de uma cópia vale a que já está no nome desejado; senão, a primeira em ordem de nome.
            guard let current = own.first(where: { nameKey($0) == nameKey(wanted) }) ?? own.first else {
                writes.append((board.id, wanted))
                continue
            }
            if nameKey(current) == nameKey(wanted) {
                if isPending { writes.append((board.id, current)) }
            } else {
                renames.append(Rename(boardID: board.id, from: current, to: wanted, writesAfterwards: isPending))
            }
        }

        // Só vai ao Lixo a cópia de quem a pessoa excluiu e já não está na biblioteca.
        let libraryIDs = Set(boards.map(\.id))
        var present = Set(folder.map { nameKey($0.name) })
        var trashes: [Action] = []
        for entry in folder {
            guard let boardID = entry.boardID, pendingTrash.contains(boardID), !libraryIDs.contains(boardID) else { continue }
            trashes.append(.trash(boardID, fileName: entry.name))
            present.remove(nameKey(entry.name))
        }

        // Um `move` nunca sobrescreve: se o destino ainda estiver ocupado depois do Lixo e dos `move` anteriores, o mural fica no
        // nome atual (e a gravação pendente vai para ele). O nome desejado já evita os nomes ocupados; esta é a rede de segurança.
        var moves: [Action] = []
        for rename in renames.sorted(by: { precedes($0.from, $1.from) }) {
            if present.contains(nameKey(rename.to)) {
                if rename.writesAfterwards { writes.append((rename.boardID, rename.from)) }
            } else {
                present.remove(nameKey(rename.from))
                present.insert(nameKey(rename.to))
                moves.append(.move(rename.boardID, from: rename.from, to: rename.to))
                if rename.writesAfterwards { writes.append((rename.boardID, rename.to)) }
            }
        }

        let writeActions = writes.sorted { precedes($0.fileName, $1.fileName) }.map { Action.write($0.boardID, fileName: $0.fileName) }
        return DriveMirrorPlan(actions: trashes + boardRenames + moves + writeActions)
    }

    /// O nome do pacote para um mural: seguro para qualquer volume, com ".mural".
    ///
    /// Troca `/` e `:` por `-`; tira os caracteres de controle, os espaços das pontas e os pontos do começo (nome com ponto
    /// no começo some do Finder); usa "Mural" se nada sobrar; corta em 120 caracteres e, se ainda passar de 200 bytes em UTF-8,
    /// tira caracteres do fim até caber: o volume aceita 255 bytes por nome, e o sufixo do id e ".mural" somam até 45.
    public static func fileName(for name: String) -> String {
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar.properties.generalCategory == .control { return nil }
            return scalar == "/" || scalar == ":" ? "-" : scalar
        }
        var cleaned = Substring(String(String.UnicodeScalarView(scalars)))
        while let first = cleaned.first, first == "." || first.isWhitespace { cleaned.removeFirst() }
        cleaned = cleaned.prefix(maximumNameLength)
        while cleaned.utf8.count > maximumNameBytes { cleaned.removeLast() }
        while let last = cleaned.last, last.isWhitespace { cleaned.removeLast() }
        if cleaned.isEmpty { cleaned = fallbackName[...] }
        return String(cleaned) + packageExtension
    }

    private static let packageExtension = ".mural"
    private static let fallbackName = "Mural"
    private static let maximumNameLength = 120
    private static let maximumNameBytes = 200

    private struct FolderEntry {
        var name: String
        var boardID: BoardID?
    }

    private struct Rename {
        var boardID: BoardID
        var from: String
        var to: String
        var writesAfterwards: Bool
    }

    /// O nome novo do mural quando a pessoa renomeou a única cópia dele no Finder; `nil` se não foi isso. Compara a base do arquivo
    /// (sem ".mural" e sem o sufixo do próprio id) com a base do nome que a cópia tinha ao ser gravada, e só aceita se o mural não
    /// mudou de nome no app desde então.
    private static func finderRename(for board: BoardManifest, copies: [String], copyNames: [String: String]) -> String? {
        guard copies.count == 1, let file = copies.first, let copyName = copyNames[file], board.name == copyName else { return nil }
        let uuid = board.id.rawValue.uuidString
        var fileBase = stripped(file, suffix: packageExtension)
        for suffix in [" (\(uuid.prefix(8)))", " (\(uuid))"] where fileBase.lowercased().hasSuffix(suffix.lowercased()) {
            fileBase = String(fileBase.dropLast(suffix.count))
            break
        }
        let expectedBase = stripped(fileName(for: copyName), suffix: packageExtension)
        guard !fileBase.trimmingCharacters(in: .whitespaces).isEmpty, fileBase != expectedBase else { return nil }
        let name = BoardName.sanitized(fileBase)
        return name == board.name ? nil : name
    }

    private static func stripped(_ name: String, suffix: String) -> String {
        name.lowercased().hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }

    /// Só os murais da própria pessoa (só deste Mac, ou no iCloud dela) e com conteúdo neste Mac têm cópia.
    private static func hasCopy(_ board: BoardManifest, awaitingFirstFetch: Set<BoardID>) -> Bool {
        guard !awaitingFirstFetch.contains(board.id) else { return false }
        switch board.cloud?.database {
        case nil, .private: return true
        case .shared: return false
        }
    }

    /// A ordem em que os murais recebem nomes: pelo nome, como o Finder ordena, e pelo id no empate.
    private static func boardOrder(_ lhs: BoardManifest, _ rhs: BoardManifest) -> Bool {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    /// A ordem dos nomes de arquivo; o desempate pelo texto mantém a saída igual qualquer que seja a ordem do dicionário.
    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs < rhs
        }
    }

    /// Nomes de arquivo se comparam sem diferença de maiúsculas, como no volume padrão do Mac.
    private static func nameKey(_ name: String) -> String {
        name.lowercased()
    }

    /// O nome do pacote do mural: `fileName(for:)`; com o sufixo do id se um mural anterior já tem o nome ou se a pasta o tem
    /// ocupado por um pacote de outro mural (ou ilegível); e com o id inteiro se até esse estiver ocupado. Assim a cópia que já
    /// está na pasta mantém o nome, e uma troca de nomes entre murais passa por nomes com sufixo, que voltam ao simples na
    /// rodada seguinte.
    private static func desiredName(for board: BoardManifest, handedOut: Set<String>, occupants: [String: [BoardID?]]) -> String {
        let plain = fileName(for: board.name)
        let base = String(plain.dropLast(packageExtension.count))
        let uuid = board.id.rawValue.uuidString.uppercased()
        for candidate in [plain, "\(base) (\(uuid.prefix(8)))\(packageExtension)"] {
            let key = nameKey(candidate)
            let isTakenByAnotherPackage = (occupants[key] ?? []).contains { $0 != board.id }
            if !handedOut.contains(key), !isTakenByAnotherPackage { return candidate }
        }
        return "\(base) (\(uuid))\(packageExtension)"
    }
}
