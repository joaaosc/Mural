import Foundation
import MuralKit

/// O trabalho de arquivo na pasta Mural do iCloud Drive, fora do Main Actor: listar o que há, gravar, renomear e levar ao Lixo as
/// cópias dos murais. Não decide nada (quem decide é `DriveMirrorPlan`, executado por `DriveMirrorController`).
///
/// Toda leitura, gravação, movimento e exclusão na pasta passa por `NSFileCoordinator`, e o trabalho de arquivo roda dentro do bloco
/// de acesso, numa fila própria. A pasta vem de `documents`, chamada só aqui dentro: `url(forUbiquityContainerIdentifier:)` pode
/// demorar e nunca deve rodar no Main Actor. Os testes passam uma pasta temporária e um `discard` que apaga.
actor DriveMirror {
    /// A pasta `Documents` do contêiner do app no iCloud Drive; `nil` sem iCloud Drive.
    private let documents: @Sendable () -> URL?
    /// Leva ao Lixo o pacote que a coordenação liberou para exclusão.
    private let discard: @Sendable (URL) throws -> Void
    /// Onde o coordenador roda os blocos de acesso: um de cada vez.
    private let queue: OperationQueue

    init(
        documents: @escaping @Sendable () -> URL? = DriveMirror.ubiquityDocuments,
        discard: @escaping @Sendable (URL) throws -> Void = { try BoardLibrary.moveToTrash($0) }
    ) {
        self.documents = documents
        self.discard = discard
        let queue = OperationQueue()
        queue.name = "com.joaocosta.Mural.DriveMirror"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        self.queue = queue
    }

    /// A pasta `Documents` do contêiner do iCloud Drive do app; `nil` sem conta ou sem iCloud Drive. Chame fora do Main Actor.
    static func ubiquityDocuments() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: CloudSyncController.containerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// O manifesto de um pacote `.mural` de qualquer lugar (a cópia que o Finder abriu), em leitura coordenada e fora do Main
    /// Actor; `nil` se o manifesto não puder ser lido.
    static func manifest(ofPackageAt package: URL) async -> BoardManifest? {
        try? await coordinate([.readingIntent(with: package, options: [])], on: OperationQueue()) { urls in
            try BoardPackageMirror.manifest(ofPackageAt: urls[0])
        }
    }

    /// O que a pasta tem: pacotes `*.mural` e pastas que perderam a extensão.
    struct Listing: Equatable, Sendable {
        /// Nome do pacote (`*.mural`) → id do manifesto dele, ou `nil` quando o manifesto não pôde ser lido.
        var copies: [String: BoardID?] = [:]
        /// Nome do pacote → nome do mural gravado no manifesto dele (só dos legíveis).
        var names: [String: String] = [:]
        /// Pasta de primeiro nível sem `.mural` mas com manifesto legível → id do mural.
        var strays: [String: BoardID] = [:]
    }

    // MARK: Operações

    /// O que há na pasta (ver `Listing`). Cria a pasta se faltar.
    /// - Throws: `DriveMirrorError.unavailable` sem iCloud Drive.
    func scan() async throws -> Listing {
        let folder = try await ensureFolder()
        return try await Self.coordinate([.readingIntent(with: folder, options: [])], on: queue) { urls in
            try Self.copies(in: urls[0])
        }
    }

    /// Leva a cópia ao Lixo.
    func trash(_ fileName: String) async throws {
        let package = try packageURL(fileName)
        let discard = self.discard
        try await Self.coordinate([.writingIntent(with: package, options: .forDeleting)], on: queue) { urls in
            try discard(urls[0])
        }
    }

    /// Renomeia a cópia. O destino ocupado é erro: nada é sobrescrito.
    func move(from oldName: String, to newName: String) async throws {
        let source = try packageURL(oldName)
        let destination = try packageURL(newName)
        let intents = [
            NSFileAccessIntent.writingIntent(with: source, options: .forMoving),
            NSFileAccessIntent.writingIntent(with: destination, options: .forReplacing),
        ]
        try await Self.coordinate(intents, on: queue) { urls in
            try FileManager.default.moveItem(at: urls[0], to: urls[1])
        }
    }

    /// Deixa a cópia `fileName` igual ao pacote `source` (ver `BoardPackageMirror.sync`) e resolve os conflitos do iCloud Drive
    /// ficando com a versão atual.
    func write(_ source: URL, as fileName: String) async throws -> BoardPackageMirror.Outcome {
        try Self.validate(fileName)
        let folder = try await ensureFolder()
        let package = folder.appendingPathComponent(fileName, isDirectory: true)
        return try await Self.coordinate([.writingIntent(with: package, options: [])], on: queue) { urls in
            let outcome = try BoardPackageMirror.sync(from: source, to: urls[0])
            try Self.keepCurrentVersion(of: urls[0])
            return outcome
        }
    }

    // MARK: Interno

    /// O endereço do pacote `fileName` na pasta, com o nome conferido.
    private func packageURL(_ fileName: String) throws -> URL {
        try Self.validate(fileName)
        guard let folder = documents() else { throw DriveMirrorError.unavailable }
        return folder.appendingPathComponent(fileName, isDirectory: true)
    }

    /// A pasta da cópia, criada se faltar.
    private func ensureFolder() async throws -> URL {
        guard let folder = documents() else { throw DriveMirrorError.unavailable }
        if !FileManager.default.fileExists(atPath: folder.path) {
            try await Self.coordinate([.writingIntent(with: folder, options: [])], on: queue) { urls in
                try FileManager.default.createDirectory(at: urls[0], withIntermediateDirectories: true)
            }
        }
        return folder
    }

    /// Só nome de pacote `.mural`, sem `/` e sem ponto no começo (oculto): nada fora da pasta é tocado.
    private static func validate(_ fileName: String) throws {
        guard fileName.lowercased().hasSuffix(".mural"), !fileName.hasPrefix("."), !fileName.contains("/") else {
            throw DriveMirrorError.invalidFileName(fileName)
        }
    }

    /// Os pacotes `*.mural` (pastas, sem ocultos) com o id e o nome do manifesto de cada um (ilegível vira `nil`), e as pastas sem a
    /// extensão cujo manifesto é legível.
    private static func copies(in folder: URL) throws -> Listing {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var listing = Listing()
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let manifest = try? BoardPackageMirror.manifest(ofPackageAt: url)
            if url.pathExtension.lowercased() == "mural" {
                listing.copies.updateValue(manifest?.id, forKey: url.lastPathComponent)
                if let manifest { listing.names[url.lastPathComponent] = manifest.name }
            } else if let manifest {
                listing.strays[url.lastPathComponent] = manifest.id
            }
        }
        return listing
    }

    /// Resolve os conflitos do iCloud Drive ficando com a versão atual: as outras são marcadas como resolvidas e saem.
    private static func keepCurrentVersion(of package: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: package), !conflicts.isEmpty else { return }
        for version in conflicts { version.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: package)
    }

    /// Pede o acesso ao coordenador e roda `work` dentro do bloco, com os endereços que ele liberou (na ordem de `intents`).
    private static func coordinate<T: Sendable>(
        _ intents: [NSFileAccessIntent], on queue: OperationQueue, _ work: @escaping @Sendable ([URL]) throws -> T
    ) async throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        // O coordenador precisa viver até o bloco rodar.
        defer { withExtendedLifetime(coordinator) {} }
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.coordinate(with: intents, queue: queue) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(with: Result { try work(intents.map(\.url)) })
                }
            }
        }
    }
}

nonisolated enum DriveMirrorError: LocalizedError, Equatable {
    /// Sem iCloud Drive neste Mac: a pasta do contêiner não existe.
    case unavailable
    /// O nome não é de um pacote `.mural` da pasta.
    case invalidFileName(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "A pasta Mural do iCloud Drive não está disponível neste Mac."
        case .invalidFileName(let name): "O nome ‘\(name)’ não é de um pacote de mural."
        }
    }
}
