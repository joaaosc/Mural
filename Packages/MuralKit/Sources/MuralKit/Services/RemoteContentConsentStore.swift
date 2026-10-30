import Foundation

/// Murais importados de um arquivo `.mural` que ainda não têm permissão para buscar prévias de link e capas de
/// música na internet. Fica num JSON local na raiz da biblioteca, fora dos pacotes: não vai na exportação nem no iCloud.
///
/// Só entra aqui o mural importado de um arquivo; o criado no app e o recebido por convite do iCloud nunca entram.
public struct RemoteContentConsentStore: Sendable {
    public static let fileName = "RemoteContent.json"

    private struct Stored: Codable {
        var blocked: [BoardID]
    }

    private let fileURL: URL
    private var blocked: Set<BoardID>

    /// Lê o arquivo de `directory`. Arquivo ausente ou ilegível vale como vazio: o app nunca trava por causa dele.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            blocked = Set(stored.blocked)
        } else {
            blocked = []
        }
    }

    public func isBlocked(_ id: BoardID) -> Bool { blocked.contains(id) }

    /// Marca o mural recém-importado como sem permissão.
    public mutating func block(_ id: BoardID) { update { $0.insert(id) } }

    /// A pessoa permitiu as buscas deste mural.
    public mutating func allow(_ id: BoardID) { update { $0.remove(id) } }

    /// O mural foi apagado: some do arquivo.
    public mutating func forget(_ id: BoardID) { update { $0.remove(id) } }

    /// Aplica a mudança e grava só se o conjunto mudou. A falha de gravação não é propagada: no pior caso o
    /// estado volta ao do último arquivo gravado na próxima abertura.
    private mutating func update(_ change: (inout Set<BoardID>) -> Void) {
        let before = blocked
        change(&blocked)
        guard blocked != before else { return }
        save()
    }

    private func save() {
        // Ordem estável pelo texto do id, para o arquivo não mudar à toa.
        let stored = Stored(blocked: blocked.sorted { $0.description < $1.description })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
