import Foundation

/// Em que pasta fica o estado de sincronização (`SyncMetadataStore`) desta cópia do app.
///
/// A cópia de desenvolvimento e a do TestFlight podem rodar no mesmo Mac, mas falam com ambientes diferentes do iCloud (CloudKit
/// Development e Production), cada um com as suas zonas. Se as duas lessem o mesmo estado, os murais acompanhados num ambiente
/// voltariam "zona não encontrada" no outro e iriam para o Lixo como se tivessem sido apagados do iCloud.
///
/// Por isso a raiz da biblioteca guarda uma marca (`SyncEnvironment.txt`) com o ambiente a que a pasta `Sync` pertence: o primeiro
/// ambiente a rodar fica com ela, e o outro usa `Sync-<Ambiente>`. Quem usa uma cópia só (as pessoas comuns só têm a de produção)
/// fica sempre em `Sync`, com o estado que já tinha.
nonisolated enum SyncLocation {
    /// O arquivo da marca, na raiz da biblioteca. Fica fora da pasta do estado para o `SyncMetadataStore` não o ver.
    static let markerFileName = "SyncEnvironment.txt"

    /// O erro de uma marca que não dá para entender.
    enum MarkerError: Error, Equatable {
        /// A marca tem um texto que não é um ambiente conhecido. Não se adivinha: escolher errado reabriria o risco que a marca evita.
        case unrecognized(String)
    }

    /// Escolhe a pasta do estado de sincronização para o ambiente dado e, se a raiz ainda não tem marca, grava a do ambiente.
    ///
    /// Marca vazia (ou só com espaços) vale como ausente; marca com outro texto lança.
    /// - Parameters:
    ///   - root: a raiz da biblioteca (`LaunchConfiguration.libraryRoot()`).
    ///   - environment: o ambiente do iCloud desta cópia (`CloudAvailability.currentEnvironment`).
    /// - Returns: a pasta do estado e se ela é a do outro ambiente, ou seja, se o estado de `Sync` pertence à outra cópia do app.
    /// - Throws: `MarkerError.unrecognized`, ou o erro de leitura ou de gravação da marca.
    static func resolve(root: URL, environment: CloudEnvironment) throws -> (directory: URL, isOtherEnvironment: Bool) {
        let shared = root.appendingPathComponent("Sync", isDirectory: true)
        let marker = root.appendingPathComponent(markerFileName, isDirectory: false)
        guard let owner = try markerOwner(at: marker) else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(environment.rawValue.utf8).write(to: marker, options: .atomic)
            return (shared, false)
        }
        guard owner != environment else { return (shared, false) }
        return (root.appendingPathComponent("Sync-\(environment.rawValue)", isDirectory: true), true)
    }

    /// O ambiente que a marca diz; `nil` se não há marca ou ela está vazia.
    private static func markerOwner(at marker: URL) throws -> CloudEnvironment? {
        let data: Data
        do {
            data = try Data(contentsOf: marker)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let owner = CloudEnvironment(rawValue: text) else { throw MarkerError.unrecognized(text) }
        return owner
    }
}
