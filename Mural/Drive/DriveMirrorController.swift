import Foundation
import MuralKit
import Observation
import os

/// Mantém, na pasta Mural do iCloud Drive, uma cópia (`.mural`) de cada mural da própria pessoa: os só deste Mac e os dela no iCloud.
/// Os recebidos de outra pessoa nunca ganham cópia. A cópia é só uma cópia: a sincronização e o compartilhamento seguem pelo CloudKit.
///
/// Quem decide o que fazer é `DriveMirrorPlan`; aqui se junta o que o plano precisa (a biblioteca, a pasta e o que este Mac anotou) e
/// se executam as ações pelo `DriveMirror`. Uma cópia só é regravada pelo Mac onde o mural mudou (`boardChanged`) ou quando falta, e
/// só sai da pasta quando a pessoa exclui o mural neste Mac (`boardDeletedByUser`). As passadas esperam `delay` depois do primeiro
/// aviso: edição contínua copia a cada tanto tempo, não a cada gravação.
@MainActor
@Observable
final class DriveMirrorController {
    /// A chave, em `UserDefaults`, da opção de guardar as cópias (ligada por padrão, por Mac).
    static let enabledKey = "driveMirrorEnabled"

    /// O que a última cópia gravada de um mural tinha. Gravação só de zoom ou rolagem não muda a marca: não regrava a cópia.
    nonisolated struct Mark: Codable, Equatable, Sendable {
        var contentRevision: Int
        var name: String

        init(contentRevision: Int, name: String) {
            self.contentRevision = contentRevision
            self.name = name
        }

        init(_ manifest: BoardManifest) {
            self.init(contentRevision: manifest.contentRevision, name: manifest.name)
        }
    }

    /// O estado de `state.json`, com os ids como texto (legível, e estável de uma gravação para outra).
    private nonisolated struct Stored: Codable {
        var pendingWrites: [String] = []
        var pendingTrash: [String] = []
        var lastWritten: [String: Mark] = [:]
    }

    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "iCloud Drive")
    private static let stateFileName = "state.json"

    /// Murais gravados neste Mac desde a última cópia.
    @ObservationIgnored private(set) var pendingWrites: Set<BoardID> = [] {
        didSet { if pendingWrites != oldValue { saveState() } }
    }
    /// Murais que a pessoa excluiu neste Mac e cuja cópia ainda não saiu da pasta.
    @ObservationIgnored private(set) var pendingTrash: Set<BoardID> = [] {
        didSet { if pendingTrash != oldValue { saveState() } }
    }
    /// A marca da última cópia gravada por este Mac, por mural.
    @ObservationIgnored private(set) var lastWritten: [BoardID: Mark] = [:] {
        didSet { if lastWritten != oldValue { saveState() } }
    }

    private let library: BoardLibrary
    private let mirror: DriveMirror
    private let awaitingFirstFetch: @MainActor () -> Set<BoardID>
    private let isAvailable: @MainActor () -> Bool
    private let defaults: UserDefaults
    private let stateURL: URL
    private let delay: Duration
    private let launchDelay: Duration

    /// A passada esperando a hora dela: no máximo uma.
    @ObservationIgnored private var waiting: Task<Void, Never>?
    @ObservationIgnored private var isReconciling = false
    /// Chegou aviso durante a passada: outra passada vem depois dela.
    @ObservationIgnored private var passAgain = false
    @ObservationIgnored private var accountObserver: Task<Void, Never>?

    /// - Parameters:
    ///   - awaitingFirstFetch: os murais adotados do iCloud que ainda esperam o conteúdo (pacote provisório): sem cópia.
    ///   - isAvailable: se este Mac tem conta com iCloud Drive; sem ela nenhuma passada faz nada.
    ///   - stateDirectory: onde fica `state.json`, o que este Mac anotou entre uma execução e outra.
    ///   - delay: a espera, contada do primeiro aviso, até a passada.
    ///   - launchDelay: a espera até a primeira passada depois de `start()`.
    init(
        library: BoardLibrary,
        mirror: DriveMirror = DriveMirror(),
        awaitingFirstFetch: @escaping @MainActor () -> Set<BoardID> = { [] },
        isAvailable: @escaping @MainActor () -> Bool = { FileManager.default.ubiquityIdentityToken != nil },
        defaults: UserDefaults = .standard,
        stateDirectory: URL = LaunchConfiguration.libraryRoot().appendingPathComponent("DriveMirror", isDirectory: true),
        delay: Duration = .seconds(30),
        launchDelay: Duration = .seconds(5)
    ) {
        self.library = library
        self.mirror = mirror
        self.awaitingFirstFetch = awaitingFirstFetch
        self.isAvailable = isAvailable
        self.defaults = defaults
        self.stateURL = stateDirectory.appendingPathComponent(Self.stateFileName, isDirectory: false)
        self.delay = delay
        self.launchDelay = launchDelay
        if let stored = Self.loadState(from: stateURL) {
            pendingWrites = Set(stored.pendingWrites.compactMap(Self.boardID))
            pendingTrash = Set(stored.pendingTrash.compactMap(Self.boardID))
            lastWritten = Dictionary(
                stored.lastWritten.compactMap { key, mark in Self.boardID(key).map { ($0, mark) } },
                uniquingKeysWith: { first, _ in first })
        }
    }

    /// Guardar as cópias neste Mac. Ligar agenda uma passada; desligar cancela a agendada e não apaga cópia nenhuma.
    var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        }
        set {
            guard newValue != isEnabled else { return }
            withMutation(keyPath: \.isEnabled) { defaults.set(newValue, forKey: Self.enabledKey) }
            if newValue {
                schedule()
            } else {
                waiting?.cancel()
                waiting = nil
                passAgain = false
            }
        }
    }

    // MARK: Avisos

    /// O mural foi gravado neste Mac: a cópia dele precisa ser refeita.
    func boardChanged(_ id: BoardID) {
        pendingWrites.insert(id)
        schedule()
    }

    /// A lista de murais mudou (criado, renomeado, importado): as cópias que faltam ou mudaram de nome entram na próxima passada.
    func libraryChanged() {
        schedule()
    }

    /// A pessoa excluiu o mural neste Mac: a cópia dele vai ao Lixo.
    func boardDeletedByUser(_ id: BoardID) {
        pendingWrites.remove(id)
        pendingTrash.insert(id)
        schedule()
    }

    /// Agenda a primeira passada e passa a ouvir a troca de conta do iCloud.
    func start() {
        guard accountObserver == nil else { return }
        accountObserver = Task { @MainActor [weak self] in
            let changes = NotificationCenter.default.notifications(named: .NSUbiquityIdentityDidChange)
            for await _ in changes {
                guard let self else { return }
                self.accountDidChange()
            }
        }
        schedule(after: launchDelay)
    }

    /// Outra conta do iCloud Drive: o que este Mac anotou era da conta anterior. Recomeça do zero (a pasta nova recebe todas as cópias).
    func accountDidChange() {
        pendingWrites = []
        pendingTrash = []
        lastWritten = [:]
        schedule()
    }

    // MARK: Agenda

    /// Agenda uma passada para daqui a `wait` (`delay` se omitido). Já havendo uma esperando, a espera não recomeça; com uma em
    /// andamento, só se marca que falta outra depois dela.
    private func schedule(after wait: Duration? = nil) {
        guard isEnabled else { return }
        if isReconciling {
            passAgain = true
            return
        }
        guard waiting == nil else { return }
        let wait = wait ?? delay
        waiting = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            self.waiting = nil
            await self.reconcileNow()
        }
    }

    /// Roda uma passada já. Com uma em andamento, só marca que falta outra depois dela.
    func reconcileNow() async {
        waiting?.cancel()
        waiting = nil
        guard !isReconciling else {
            passAgain = true
            return
        }
        isReconciling = true
        passAgain = false
        await reconcile()
        isReconciling = false
        if passAgain {
            passAgain = false
            schedule()
        }
    }

    // MARK: Passada

    private func reconcile() async {
        guard isEnabled, isAvailable() else { return }
        let boards: [BoardManifest]
        let copies: [String: BoardID?]
        do {
            boards = try await library.listSaved().map(\.manifest)
            copies = try await mirror.scan()
        } catch {
            Self.log.error("Passada interrompida: \(String(describing: error), privacy: .public)")
            return
        }

        // Sai da lista o que não precisa de ação: mural que deixou a biblioteca, mural cuja cópia já tem o conteúdo e o nome atuais,
        // exclusão sem cópia na pasta (ou de mural que voltou).
        let current = Dictionary(boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        pendingWrites = pendingWrites.filter { id in
            guard let manifest = current[id] else { return false }
            return lastWritten[id] != Mark(manifest)
        }
        let copied = Set(copies.values.compactMap { $0 })
        pendingTrash = pendingTrash.filter { copied.contains($0) && current[$0] == nil }
        lastWritten = lastWritten.filter { current[$0.key] != nil }

        let plan = DriveMirrorPlan.make(
            boards: boards, copies: copies, pendingWrites: pendingWrites, pendingTrash: pendingTrash,
            awaitingFirstFetch: awaitingFirstFetch())
        // Um mural cujo `move` falhou não grava no nome novo: criaria uma segunda cópia ao lado da antiga.
        var failedMoves = Set<BoardID>()
        for action in plan.actions {
            guard isEnabled else { return }
            switch action {
            case .trash(let id, let fileName):
                await trash(id, fileName: fileName)
            case .move(let id, let oldName, let newName):
                if await !move(from: oldName, to: newName) { failedMoves.insert(id) }
            case .write(let id, let fileName):
                if !failedMoves.contains(id) { await write(id, fileName: fileName) }
            }
        }
    }

    private func trash(_ id: BoardID, fileName: String) async {
        do {
            try await mirror.trash(fileName)
            pendingTrash.remove(id)
            lastWritten[id] = nil
        } catch {
            Self.log.error("Cópia ‘\(fileName, privacy: .private)’ não foi ao Lixo: \(String(describing: error), privacy: .public)")
        }
    }

    /// `false` se a cópia não pôde ser renomeada (destino ocupado, por exemplo): ela fica no nome atual.
    private func move(from oldName: String, to newName: String) async -> Bool {
        do {
            try await mirror.move(from: oldName, to: newName)
            return true
        } catch {
            Self.log.error("Cópia ‘\(oldName, privacy: .private)’ não foi renomeada: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func write(_ id: BoardID, fileName: String) async {
        // O aviso sai antes de copiar: uma gravação que chegar durante a cópia o põe de volta, e a próxima passada a refaz.
        let wasPending = pendingWrites.remove(id) != nil
        var staging: URL?
        do {
            let package = try await library.exportPackage(.saved(id))
            staging = package
            // A marca é a do que foi copiado, não a do manifesto lido no começo da passada.
            let exported = try BoardPackageMirror.manifest(ofPackageAt: package)
            _ = try await mirror.write(package, as: fileName)
            lastWritten[id] = Mark(exported)
        } catch {
            if wasPending { pendingWrites.insert(id) }
            Self.log.error("Cópia ‘\(fileName, privacy: .private)’ não foi gravada: \(String(describing: error), privacy: .public)")
        }
        if let staging {
            do {
                try await library.cleanupTransfer(staging)
            } catch {
                Self.log.error("Pasta de passagem não saiu: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Estado

    private static func boardID(_ text: String) -> BoardID? {
        UUID(uuidString: text).map { BoardID(rawValue: $0) }
    }

    private static func loadState(from url: URL) -> Stored? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Stored.self, from: data)
        } catch {
            log.error("Estado das cópias ilegível: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func saveState() {
        let stored = Stored(
            pendingWrites: pendingWrites.map(\.rawValue.uuidString).sorted(),
            pendingTrash: pendingTrash.map(\.rawValue.uuidString).sorted(),
            lastWritten: Dictionary(uniqueKeysWithValues: lastWritten.map { ($0.key.rawValue.uuidString, $0.value) }))
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(stored).write(to: stateURL, options: .atomic)
        } catch {
            Self.log.error("Estado das cópias não foi gravado: \(String(describing: error), privacy: .public)")
        }
    }
}
