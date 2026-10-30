import Foundation
import os

/// Recupera e limpa o que uma queda ou um fechamento forçado deixou nas pastas da biblioteca: trocas de pacote
/// pela metade, cópias de segurança antigas e pastas temporárias de exportação e importação.
///
/// As idades protegem uma segunda cópia do app aberta ao mesmo tempo (ela usa o mesmo contêiner e pode estar no meio de
/// uma troca): só o que ficou parado por tempo de sobra é tocado. Pacote de mural nunca é apagado direto; vai para o
/// descarte injetado (o Lixo do Mac). Erro em uma entrada é registrado e a próxima segue.
struct InterruptedWorkRecovery {
    /// Uma troca em andamento leva milissegundos; um minuto parado já é queda.
    static let backupRecoveryAge: TimeInterval = 60
    /// Cópias de segurança e staging que sobraram depois de uma troca concluída.
    static let leftoverAge: TimeInterval = 6 * 3600
    /// Pastas de exportação e importação que ninguém limpou.
    static let transferAge: TimeInterval = 24 * 3600

    private static let logger = Logger(subsystem: "com.joaocosta.Mural", category: "Recuperação")

    let now: Date
    let discard: @Sendable (URL) throws -> Void
    private var fileManager: FileManager { .default }

    init(now: Date, discard: @escaping @Sendable (URL) throws -> Void) {
        self.now = now
        self.discard = discard
    }

    /// - Parameter packageName: nome fixo do pacote na pasta (o rascunho de exemplo usa `Welcome.mural`); `nil` vale `<UUID>.mural`.
    func recoverPackages(in directory: URL, packageName: String? = nil) {
        let entries = contents(of: directory)
        recoverBackups(in: directory, entries: entries, packageName: packageName)
        // Relê: a recuperação move pastas.
        let current = contents(of: directory)
        removeOldStaging(in: directory, entries: current, packageName: packageName)
        for package in current where !package.lastPathComponent.hasPrefix(".") && package.pathExtension == "mural" {
            removeOldHardLinkBackups(in: package)
        }
    }

    func removeOldEntries(in directory: URL) {
        for entry in contents(of: directory) where age(of: entry) >= Self.transferAge {
            do { try fileManager.removeItem(at: entry) } catch { log("remover \(entry.lastPathComponent)", error) }
        }
    }

    // MARK: Cópias de segurança de pacote

    private func recoverBackups(in directory: URL, entries: [URL], packageName: String?) {
        let backups = entries.compactMap { url in parse(url.lastPathComponent, marker: ".mural-backup-").map { (url, $0) } }
            .sorted { age(of: $0.0) < age(of: $1.0) }
        for (backup, id) in backups where age(of: backup) >= Self.backupRecoveryAge {
            let package = directory.appendingPathComponent(packageName ?? "\(id.uuidString).mural", isDirectory: true)
            do {
                if !fileManager.fileExists(atPath: package.path) {
                    // O staging completo é a versão mais nova: a queda veio entre as duas trocas.
                    if let staging = newestCompleteStaging(for: id, in: directory, entries: entries) {
                        try fileManager.moveItem(at: staging, to: package)
                        try discard(backup)
                    } else {
                        try fileManager.moveItem(at: backup, to: package)
                    }
                } else if age(of: backup) >= Self.leftoverAge {
                    try discard(backup)
                }
            } catch {
                log("recuperar \(backup.lastPathComponent)", error)
            }
        }
    }

    private func newestCompleteStaging(for id: UUID, in directory: URL, entries: [URL]) -> URL? {
        entries.filter { parse($0.lastPathComponent, marker: ".mural-staging-") == id && isCompletePackage($0) }
            .min { age(of: $0) < age(of: $1) }
    }

    /// Mesma regra de `BoardLibrary.validateCompletePackage`.
    private func isCompletePackage(_ package: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: package.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        return ["manifest.json", "board.json", "view-state.json", "Items"].allSatisfy {
            fileManager.fileExists(atPath: package.appendingPathComponent($0).path)
        }
    }

    private func removeOldStaging(in directory: URL, entries: [URL], packageName: String?) {
        for entry in entries {
            guard let id = parse(entry.lastPathComponent, marker: ".mural-staging-"), age(of: entry) >= Self.leftoverAge,
                fileManager.fileExists(atPath: directory.appendingPathComponent(packageName ?? "\(id.uuidString).mural").path)
            else { continue }
            do { try fileManager.removeItem(at: entry) } catch { log("remover \(entry.lastPathComponent)", error) }
        }
    }

    // MARK: Hard links de backup dentro do pacote

    /// `.<arquivo>.backup-<UUID>`: cópia por hard link de um arquivo que já foi substituído; o arquivo principal existe.
    private func removeOldHardLinkBackups(in package: URL) {
        for entry in contents(of: package) {
            let name = entry.lastPathComponent
            guard name.hasPrefix("."), let range = name.range(of: ".backup-", options: .backwards),
                UUID(uuidString: String(name[range.upperBound...])) != nil, age(of: entry) >= Self.leftoverAge
            else { continue }
            do { try fileManager.removeItem(at: entry) } catch { log("remover \(name)", error) }
        }
    }

    // MARK: Apoio

    /// Extrai o UUID de `.<UUID><marker><UUID>`; `nil` se o nome não segue o formato.
    private func parse(_ name: String, marker: String) -> UUID? {
        guard name.hasPrefix("."), let range = name.range(of: marker) else { return nil }
        let id = String(name[name.index(after: name.startIndex)..<range.lowerBound])
        guard UUID(uuidString: String(name[range.upperBound...])) != nil else { return nil }
        return UUID(uuidString: id)
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Idade pela data de modificação; sem data legível conta como recém-criado, para não tocar no que não se entende.
    private func age(of url: URL) -> TimeInterval {
        guard let date = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return 0 }
        return now.timeIntervalSince(date)
    }

    private func log(_ action: String, _ error: Error) {
        Self.logger.error("Falha ao \(action, privacy: .public): \(String(describing: error), privacy: .public)")
    }
}
