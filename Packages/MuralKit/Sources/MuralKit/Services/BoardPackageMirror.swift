import Foundation

/// Mantém uma cópia de pacote `.mural` (a do iCloud Drive) igual a um pacote de origem já montado (`BoardLibrary.exportPackage`),
/// regravando só o que mudou: cada JSON só se os bytes mudaram, e de `Items/` só os arquivos novos, apagando os que saíram. A mídia
/// é imutável e de nome único: o nome basta. Síncrono, para rodar dentro de um bloco de `NSFileCoordinator`.
///
/// A ordem mantém a cópia coerente se a gravação for interrompida: a mídia nova entra antes dos JSON que a citam, a mídia que saiu
/// só é apagada depois de o `board.json` deixar de citá-la, e o `manifest.json` vai por último, como marca de que a cópia está
/// completa. A pasta que vai conter o pacote precisa existir: ela não é criada aqui.
public enum BoardPackageMirror {
    /// O que uma chamada de `sync` mudou no destino.
    public struct Outcome: Equatable, Sendable {
        /// O pacote não existia e foi criado.
        public var createdPackage: Bool
        /// JSON gravados: os que faltavam ou tinham bytes diferentes.
        public var rewrittenFiles: Int
        /// Arquivos de `Items/` copiados para o destino.
        public var addedItems: Int
        /// Arquivos de `Items/` apagados do destino.
        public var removedItems: Int

        public var changedAnything: Bool { createdPackage || rewrittenFiles > 0 || addedItems > 0 || removedItems > 0 }

        public init(createdPackage: Bool = false, rewrittenFiles: Int = 0, addedItems: Int = 0, removedItems: Int = 0) {
            self.createdPackage = createdPackage
            self.rewrittenFiles = rewrittenFiles
            self.addedItems = addedItems
            self.removedItems = removedItems
        }
    }

    private static let manifestName = "manifest.json"
    private static let documentNames = ["board.json", "view-state.json"]
    private static let itemsName = "Items"

    /// Deixa o pacote `destination` igual ao pacote `source`, e devolve o que precisou mudar.
    ///
    /// - Throws: `BoardPackageMirrorError`. A origem incompleta, o destino que não é pasta e o destino que é de outro mural
    ///   são recusados antes de qualquer gravação.
    public static func sync(from source: URL, to destination: URL) throws -> Outcome {
        do {
            return try performSync(from: source, to: destination)
        } catch let error as BoardPackageMirrorError {
            throw error
        } catch {
            throw BoardPackageMirrorError.io(String(describing: error))
        }
    }

    /// Lê só o `manifest.json` de um pacote (mesma decodificação da biblioteca, com a trava de esquema futuro).
    public static func manifest(ofPackageAt package: URL) throws -> BoardManifest {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
            }
            let data = try Data(contentsOf: package.appendingPathComponent(manifestName, isDirectory: false))
            let manifest = try decoder.decode(BoardManifest.self, from: data)
            guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
                throw BoardPackageMirrorError.unreadableManifest("formato \(manifest.schemaVersion), mais novo que o desta versão")
            }
            return manifest
        } catch let error as BoardPackageMirrorError {
            throw error
        } catch {
            throw BoardPackageMirrorError.unreadableManifest(String(describing: error))
        }
    }

    private static func performSync(from source: URL, to destination: URL) throws -> Outcome {
        let fileManager = FileManager.default
        try requireCompletePackage(at: source)
        let sourceManifest = try manifest(ofPackageAt: source)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            do {
                var outcome = try bringUpToDate(destination, from: source)
                outcome.createdPackage = true
                return outcome
            } catch {
                // Um pacote novo que não ficou completo não fica para trás: a pasta sem manifesto nunca seria reaproveitada.
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }
        guard isDirectory.boolValue else { throw BoardPackageMirrorError.destinationNotAPackage(destination) }
        // Só a pasta de outro mural trava. Sem manifesto legível, é cópia nossa danificada: segue e regrava.
        if let existing = boardID(ofPackageAt: destination), existing != sourceManifest.id {
            throw BoardPackageMirrorError.destinationIsAnotherBoard(existing)
        }
        return try bringUpToDate(destination, from: source)
    }

    /// Deixa a pasta `destination`, que já existe, igual à origem, na ordem que mantém a cópia coerente.
    private static func bringUpToDate(_ destination: URL, from source: URL) throws -> Outcome {
        let fileManager = FileManager.default
        var outcome = Outcome()
        let sourceItems = source.appendingPathComponent(itemsName, isDirectory: true)
        let destinationItems = destination.appendingPathComponent(itemsName, isDirectory: true)
        var itemsIsDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: destinationItems.path, isDirectory: &itemsIsDirectory) {
            try fileManager.createDirectory(at: destinationItems, withIntermediateDirectories: false)
        } else if !itemsIsDirectory.boolValue {
            throw BoardPackageMirrorError.io("\(itemsName) existe no destino e não é pasta")
        }
        let sourceNames = try itemNames(in: sourceItems)
        let destinationNames = try itemNames(in: destinationItems)

        // A mídia nova entra antes dos JSON que a citam.
        for name in sourceNames.subtracting(destinationNames).sorted() {
            try fileManager.copyItem(
                at: sourceItems.appendingPathComponent(name, isDirectory: false),
                to: destinationItems.appendingPathComponent(name, isDirectory: false))
            outcome.addedItems += 1
        }
        for name in documentNames {
            if try replaceIfChanged(name, from: source, to: destination) { outcome.rewrittenFiles += 1 }
        }
        // A mídia que saiu só é apagada depois de o board deixar de citá-la.
        for name in destinationNames.subtracting(sourceNames).sorted() {
            try fileManager.removeItem(at: destinationItems.appendingPathComponent(name, isDirectory: false))
            outcome.removedItems += 1
        }
        // O manifesto por último: com ele no lugar, a cópia está completa.
        if try replaceIfChanged(manifestName, from: source, to: destination) {
            outcome.rewrittenFiles += 1
        }
        return outcome
    }

    /// O pacote de origem precisa ter os três JSON (arquivos) e `Items/` (pasta).
    private static func requireCompletePackage(at package: URL) throws {
        func exists(_ name: String, asDirectory: Bool) -> Bool {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: package.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue == asDirectory
        }
        guard ([manifestName] + documentNames).allSatisfy({ exists($0, asDirectory: false) }), exists(itemsName, asDirectory: true) else {
            throw BoardPackageMirrorError.sourceIncomplete(package)
        }
    }

    /// O id do manifesto de um pacote, mesmo de um formato mais novo que o desta versão: basta para saber de quem é a pasta.
    private static func boardID(ofPackageAt package: URL) -> BoardID? {
        struct Identity: Decodable {
            var id: BoardID
        }
        guard let data = try? Data(contentsOf: package.appendingPathComponent(manifestName, isDirectory: false)) else { return nil }
        return (try? JSONDecoder().decode(Identity.self, from: data))?.id
    }

    /// Nomes dos arquivos comuns, não ocultos e de nome seguro de uma pasta de mídia; o resto não é da cópia.
    private static func itemNames(in directory: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        var names = Set<String>()
        for url in urls {
            let name = url.lastPathComponent
            guard BoardRepository.isSafeAssetName(name),
                (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            names.insert(name)
        }
        return names
    }

    /// Grava `name` no destino só se faltar ou tiver bytes diferentes. `true` se gravou.
    private static func replaceIfChanged(_ name: String, from source: URL, to destination: URL) throws -> Bool {
        let data = try Data(contentsOf: source.appendingPathComponent(name, isDirectory: false))
        let target = destination.appendingPathComponent(name, isDirectory: false)
        if let current = try? Data(contentsOf: target), current == data { return false }
        try data.write(to: target, options: .atomic)
        return true
    }
}

public enum BoardPackageMirrorError: Error, Equatable, Sendable {
    /// Falta `manifest.json`, `board.json`, `view-state.json` ou `Items/` no pacote de origem.
    case sourceIncomplete(URL)
    /// O destino existe e não é pasta.
    case destinationNotAPackage(URL)
    /// A pasta de destino tem o manifesto de outro mural: nunca é sobrescrita.
    case destinationIsAnotherBoard(BoardID)
    /// O `manifest.json` não pôde ser lido: falta, está danificado ou é de um formato mais novo que o desta versão.
    case unreadableManifest(String)
    /// Falha ao ler, copiar, gravar ou apagar um arquivo.
    case io(String)
}
