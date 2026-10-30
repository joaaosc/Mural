import Foundation
import MuralKit
import Synchronization

/// Os arquivos das cópias de edição: o conteúdo copiado gravado numa pasta temporária, aberto num app de fora para a
/// pessoa editar e lido de volta antes de colar.
///
/// Onde cada tipo fica foi decidido por teste real no macOS 27. O Texto edita no lugar um arquivo dentro do contêiner do
/// próprio Mural (`Roots.inside`). A Pré-Visualização trata um arquivo no contêiner de outro app como somente leitura
/// ("O documento original não pode ser alterado…") e cria uma duplicata, mas edita no lugar um arquivo na pasta Downloads
/// de verdade (`Roots.visible`). A leitura é sempre coordenada: o editor aberto grava o que ainda não foi salvo antes de
/// entregar o arquivo. Apagar de forma coordenada fecha a janela da Pré-Visualização; o Texto mantém a dele aberta, sem
/// avisar.
///
/// Nenhuma função daqui lê a data de um arquivo: a data de criação da cópia vai no nome da pasta, e é por ela que a
/// limpeza decide o que é velho. Assim o manifesto de privacidade do app não precisa declarar o acesso a datas de arquivos.
nonisolated enum PasteEditFiles {
    /// As duas raízes onde as cópias ficam.
    nonisolated struct Roots: Equatable, Sendable {
        /// Dentro do contêiner do app: o que o Texto edita no lugar.
        let inside: URL
        /// Numa pasta que a pessoa enxerga (`~/Downloads/Edições do Mural`): o que a Pré-Visualização edita no lugar.
        let visible: URL

        /// A raiz onde o tipo é gravado: texto em `inside`; imagem e PDF em `visible`.
        func root(for kind: PasteEditKind) -> URL {
            switch kind {
            case .text: inside
            case .image, .pdf: visible
            }
        }
    }

    /// Uma edição em andamento: onde está a cópia e quando foi criada.
    nonisolated struct Session: Equatable, Sendable {
        let id: UUID
        let kind: PasteEditKind
        /// A pasta só desta edição, dentro da raiz do tipo.
        let folder: URL
        /// O arquivo gravado dentro da pasta. O editor pode renomeá-lo ao salvar; ver ``read(_:timeout:)``.
        let file: URL
        let createdAt: Date
    }

    /// Por que uma cópia de edição não pôde ser gravada ou lida.
    nonisolated enum Failure: LocalizedError, Equatable {
        /// O arquivo sumiu e não há um único arquivo no lugar dele.
        case missing
        /// A edição ficou vazia.
        case empty
        /// O arquivo existe, mas não pôde ser lido ou não tem o formato esperado.
        case unreadable
        /// O conteúdo copiado não é de um tipo que se edita fora do Mural.
        case unsupported

        var errorDescription: String? {
            switch self {
            case .missing: "A cópia em edição não foi encontrada; ela pode ter sido movida ou apagada."
            case .empty: "A edição está vazia."
            case .unreadable: "A cópia em edição não pôde ser lida."
            case .unsupported: "Esse conteúdo não pode ser editado fora do Mural."
            }
        }
    }

    /// Quanto tempo uma cópia esquecida fica antes de a limpeza apagá-la: um dia.
    static let maxAge: TimeInterval = 24 * 60 * 60

    // MARK: Nomes

    /// O nome da pasta de uma edição: `yyyyMMdd-HHmmss-<UUID>`, com a data em UTC. A data no nome é o que a limpeza
    /// (``sweep(roots:keeping:now:maxAge:)``) lê, sem consultar datas de arquivos.
    static func folderName(id: UUID, createdAt: Date) -> String {
        "\(stampFormatter().string(from: createdAt))-\(id.uuidString)"
    }

    /// A data de criação que o nome de uma pasta guarda.
    /// - Returns: `nil` para qualquer nome que não seja o de ``folderName(id:createdAt:)``.
    static func creationDate(ofFolderNamed name: String) -> Date? {
        let stampLength = 15
        guard name.count > stampLength + 1 else { return nil }
        let separator = name.index(name.startIndex, offsetBy: stampLength)
        guard name[separator] == "-" else { return nil }
        let stamp = String(name[..<separator])
        let rest = String(name[name.index(after: separator)...])
        guard UUID(uuidString: rest) != nil else { return nil }
        return stampFormatter().date(from: stamp)
    }

    /// O nome do arquivo da cópia: "Colar em <mural>.<extensão>". Barra e dois-pontos viram hífen, espaços e quebras de linha
    /// repetidos viram um espaço, o nome do mural é cortado em 80 caracteres e, sem nome, fica "Colar no mural".
    static func fileName(boardName: String, kind: PasteEditKind) -> String {
        let cleaned =
            boardName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let name = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
        let base = name.isEmpty ? "Colar no mural" : "Colar em \(name)"
        return "\(base).\(kind.fileExtension)"
    }

    private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    // MARK: Gravar

    /// Grava o conteúdo copiado em `<raiz do tipo>/<nome da pasta>/<nome do arquivo>` e devolve a edição.
    ///
    /// Texto vai em UTF-8 com o atributo `com.apple.TextEncoding`, para o editor não adivinhar a codificação. Imagem em
    /// outro formato é convertida para PNG; imagem em PNG e PDF vão como vieram. Se algo falhar, a pasta criada é removida;
    /// conteúdo de outro tipo falha antes de criar qualquer coisa.
    /// - Throws: ``Failure/unsupported`` quando o conteúdo não combina com o tipo; ``Failure/unreadable`` quando a imagem não
    ///   converte; o erro do sistema quando a gravação falha.
    @concurrent
    static func write(
        _ content: PasteboardImporter.Content, as kind: PasteEditKind, boardName: String, roots: Roots,
        id: UUID = UUID(), now: Date = .now
    ) async throws -> Session {
        let isText: Bool
        let payload: Data
        switch (content, kind) {
        case (.text(let text), .text):
            isText = true
            payload = Data(text.utf8)
        case (.data(let data, let fileExtension, let itemKind, _), .image) where fileExtension == "png" && itemKind == .image:
            isText = false
            payload = data
        case (.imageNeedingConversion(let data), .image):
            guard let png = await PasteboardImporter.pngData(from: data) else { throw Failure.unreadable }
            isText = false
            payload = png
        case (.data(let data, let fileExtension, let itemKind, _), .pdf) where fileExtension == "pdf" && itemKind == .pdf:
            isText = false
            payload = data
        default:
            throw Failure.unsupported
        }

        let folder = roots.root(for: kind).appendingPathComponent(folderName(id: id, createdAt: now), isDirectory: true)
        let file = folder.appendingPathComponent(fileName(boardName: boardName, kind: kind), isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try payload.write(to: file)
            if isText { setTextEncodingAttribute(on: file) }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return Session(id: id, kind: kind, folder: folder, file: file, createdAt: now)
    }

    /// Marca o arquivo como UTF-8 (`utf-8;134217984`: o nome da codificação e o código do CFStringEncoding). Sem sucesso, o
    /// editor volta a adivinhar; por isso a falha é ignorada.
    private static func setTextEncodingAttribute(on file: URL) {
        let value = Data("utf-8;134217984".utf8)
        _ = value.withUnsafeBytes { bytes in
            setxattr(file.path, "com.apple.TextEncoding", bytes.baseAddress, bytes.count, 0, 0)
        }
    }

    // MARK: Ler

    /// Lê a edição de volta, de forma coordenada: o editor que ainda tem alterações não salvas as grava antes.
    ///
    /// Se o editor renomeou o arquivo, vale o único arquivo comum que sobrou na pasta. Se a coordenação não termina no
    /// `timeout` (um editor travado num diálogo, por exemplo), cancela-a e lê a última versão salva, sem coordenar.
    /// - Returns: texto como `.text`; imagem PNG como `.data` e outra imagem como `.imageNeedingConversion`; PDF como
    ///   `.data`. Nunca `.files`.
    /// - Throws: ``Failure/missing``, ``Failure/empty`` (texto em branco ou arquivo vazio) ou ``Failure/unreadable``.
    @concurrent
    static func read(_ session: Session, timeout: Duration = .seconds(5)) async throws -> PasteboardImporter.Content {
        let url = try locate(session)
        switch session.kind {
        case .text:
            let text: String
            do {
                text = try await coordinated(url, deleting: false, timeout: timeout) { file in
                    var encoding = String.Encoding.utf8
                    return try String(contentsOf: file, usedEncoding: &encoding)
                }
            } catch {
                throw Failure.unreadable
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
            return .text(text)
        case .image:
            let data = try await readData(url, timeout: timeout)
            if data.starts(with: pngSignature) {
                return .data(data, fileExtension: "png", kind: .image, title: "Imagem colada")
            }
            return .imageNeedingConversion(data)
        case .pdf:
            let data = try await readData(url, timeout: timeout)
            guard data.starts(with: Data("%PDF".utf8)) else { throw Failure.unreadable }
            return .data(data, fileExtension: "pdf", kind: .pdf, title: "PDF colado")
        }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func readData(_ url: URL, timeout: Duration) async throws -> Data {
        let data: Data
        do {
            data = try await coordinated(url, deleting: false, timeout: timeout) { try Data(contentsOf: $0) }
        } catch {
            throw Failure.unreadable
        }
        guard !data.isEmpty else { throw Failure.empty }
        return data
    }

    /// O arquivo da edição: o gravado ou, se ele sumiu, o único arquivo comum que restou na pasta.
    private static func locate(_ session: Session) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: session.file.path) { return session.file }
        let entries =
            (try? fileManager.contentsOfDirectory(
                at: session.folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        let files = entries.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard files.count == 1, let only = files.first else { throw Failure.missing }
        return only
    }

    // MARK: Apagar

    /// Apaga a edição: os arquivos que restam na pasta (de forma coordenada, para o editor aberto soltá-los), a pasta e, se
    /// ficou vazia, a raiz dela (a pasta "Edições do Mural" no Downloads). Faz o que puder e nunca falha.
    @concurrent
    static func remove(_ session: Session) async {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(at: session.folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            try? await coordinated(entry, deleting: true, timeout: .seconds(5)) { try FileManager.default.removeItem(at: $0) }
        }
        try? fileManager.removeItem(at: session.folder)
        removeIfEmpty(session.folder.deletingLastPathComponent())
    }

    private static func removeIfEmpty(_ directory: URL) {
        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
            entries.isEmpty
        else { return }
        try? fileManager.removeItem(at: directory)
    }

    // MARK: Limpeza

    /// Apaga as pastas de edição esquecidas nas duas raízes: as que têm o nome de ``folderName(id:createdAt:)`` com data
    /// mais antiga que `maxAge`, menos as de `keeping` (edições ainda abertas). Pastas com outro nome não são tocadas. Depois,
    /// remove a raiz visível se ficou vazia. A idade vem só do nome: nenhuma data de arquivo é consultada.
    /// - Returns: as pastas removidas.
    @discardableResult
    static func sweep(
        roots: Roots, keeping active: Set<URL> = [], now: Date = .now, maxAge: TimeInterval = maxAge
    ) -> [URL] {
        let fileManager = FileManager.default
        let keep = Set(active.map(\.standardizedFileURL))
        var removed: [URL] = []
        for root in [roots.inside, roots.visible] {
            let entries =
                (try? fileManager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                guard let created = creationDate(ofFolderNamed: entry.lastPathComponent),
                    now.timeIntervalSince(created) > maxAge,
                    !keep.contains(entry.standardizedFileURL)
                else { continue }
                if (try? fileManager.removeItem(at: entry)) != nil { removed.append(entry) }
            }
        }
        removeIfEmpty(roots.visible)
        return removed
    }

    // MARK: Coordenação

    /// Guarda o coordenador só para cancelá-lo de outra tarefa: `cancel()` é seguro entre threads.
    private final class CoordinatorBox: @unchecked Sendable {
        let coordinator = NSFileCoordinator(filePresenter: nil)

        func cancel() { coordinator.cancel() }
    }

    /// `NSFileAccessIntent` não é `Sendable`; o acessor só lê o endereço dele, depois de a coordenação o entregar.
    private final class IntentBox: @unchecked Sendable {
        let intent: NSFileAccessIntent

        init(_ intent: NSFileAccessIntent) { self.intent = intent }
    }

    /// Decide, sob uma trava só, quem roda `body`: o acessor da coordenação ou a leitura direta (prazo vencido ou erro do
    /// coordenador). Só um dos dois roda, uma vez, e só o primeiro resultado segue.
    private final class Gate<Value: Sendable>: Sendable {
        private enum Phase {
            /// Ninguém começou ainda.
            case waiting
            /// O acessor recebeu o arquivo coordenado: o prazo não vale mais.
            case coordinating
            /// O prazo venceu ou a coordenação falhou: vale a leitura direta.
            case direct
        }

        private let phase = Mutex(Phase.waiting)
        private let continuation: Mutex<CheckedContinuation<Result<Value, Error>, Never>?>
        private let timer = Mutex<Task<Void, Never>?>(nil)

        init(_ continuation: CheckedContinuation<Result<Value, Error>, Never>) {
            self.continuation = Mutex(continuation)
        }

        func setTimer(_ task: Task<Void, Never>) {
            timer.withLock { $0 = task }
        }

        /// O acessor quer rodar `body`. Falso se a leitura direta já ficou com a vez.
        func claimCoordinated() -> Bool { claim(.coordinating) }

        /// O prazo venceu ou a coordenação falhou. Falso se o acessor já ficou com a vez.
        func claimDirect() -> Bool { claim(.direct) }

        private func claim(_ next: Phase) -> Bool {
            phase.withLock { phase in
                guard phase == .waiting else { return false }
                phase = next
                return true
            }
        }

        func finish(_ result: Result<Value, Error>) {
            let pending = continuation.withLock { continuation -> CheckedContinuation<Result<Value, Error>, Never>? in
                defer { continuation = nil }
                return continuation
            }
            guard let pending else { return }
            timer.withLock { $0?.cancel() }
            pending.resume(returning: result)
        }
    }

    /// Roda `body` com o arquivo coordenado (leitura ou exclusão). Se o `timeout` passa antes de a coordenação começar, ou se
    /// o coordenador devolve um erro, cancela a coordenação e roda `body` direto, sem coordenar. Em nenhum caso `body` roda
    /// duas vezes.
    @concurrent
    private static func coordinated<Value: Sendable>(
        _ url: URL, deleting: Bool, timeout: Duration, _ body: @escaping @Sendable (URL) throws -> Value
    ) async throws -> Value {
        let box = CoordinatorBox()
        let outcome: Result<Value, Error> = await withCheckedContinuation { continuation in
            let gate = Gate<Value>(continuation)
            let intent = IntentBox(
                deleting
                    ? NSFileAccessIntent.writingIntent(with: url, options: .forDeleting)
                    : NSFileAccessIntent.readingIntent(with: url))
            gate.setTimer(
                Task {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled, gate.claimDirect() else { return }
                    box.cancel()
                    gate.finish(Result { try body(url) })
                })
            box.coordinator.coordinate(with: [intent.intent], queue: OperationQueue()) { error in
                if error != nil {
                    guard gate.claimDirect() else { return }
                    gate.finish(Result { try body(url) })
                } else {
                    guard gate.claimCoordinated() else { return }
                    gate.finish(Result { try body(intent.intent.url) })
                }
            }
        }
        return try outcome.get()
    }
}
