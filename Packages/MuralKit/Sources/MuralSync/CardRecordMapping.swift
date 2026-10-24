import Foundation
import MuralKit

/// Os erros ao converter entre o conteúdo do mural e os registros do iCloud.
public enum CardRecordMappingError: Error, Equatable, Sendable {
    /// Os campos do cartão passam de `CardRecordMapping.maximumFieldBytes`, e o iCloud recusaria o registro inteiro.
    case recordTooLarge(UUID)
    /// O registro não pode ser lido: é de outro tipo, o nome não é o esperado, falta um campo obrigatório, um campo tem o tipo
    /// errado ou o JSON de um campo está ilegível. A mensagem diz qual.
    case invalidRecord(String)
}

/// O que `CardRecordMapping.card(from:)` entendeu de um registro de cartão.
public enum CardDecoding: Equatable, Sendable {
    /// O cartão, sempre na forma `SharedFieldPolicy.shared`, e o número de empilhamento, quando o registro trazia um.
    case card(BoardItem, layer: Double?)
    /// Registro de um app mais novo: tipo de cartão, cor ou versão do formato que esta build não conhece. Quem chama o deixa como
    /// está no iCloud, sem apagar nem regravar, senão perderia o que o app novo guardou.
    case unsupported
}

/// Traduz o conteúdo do mural (cartão, texto livre, nome do mural e arquivo de mídia) de e para os campos de um registro do iCloud.
///
/// As datas viajam como `.double(timeIntervalSinceReferenceDate)`, nunca como um tipo data: a ida e volta precisa devolver o mesmo
/// valor, bit a bit. Se o iCloud devolvesse uma data diferente da enviada, o Mac veria diferença entre o cartão que tem e o que o
/// iCloud devolveu e o reenviaria para sempre.
public enum CardRecordMapping {
    /// O limite dos campos de um cartão, em bytes: a soma dos tamanhos em UTF-8 dos textos e dos dados. O iCloud recusa um registro
    /// com mais de 1 MB (os arquivos ficam de fora), e a folga cobre o que não entra na soma: nomes dos campos, números e cabeçalho.
    public static let maximumFieldBytes = 900_000

    // MARK: Cartão

    /// Os campos do registro de um cartão, com o número de empilhamento `layer`.
    ///
    /// O cartão deve chegar na forma `SharedFieldPolicy.shared`: sem as frases curtas, e com o link e a música sem os arquivos e
    /// sem o estado da prévia, que são de cada Mac. Por segurança a forma `shared` é aplicada de novo aqui, então nada local sai.
    /// Lista, metadados da imagem, link, lembrete, música e anexos viajam como JSON; campo sem valor não vira campo do registro.
    /// - Throws: `CardRecordMappingError.recordTooLarge` se os campos somam mais de `maximumFieldBytes`.
    public static func fields(for item: BoardItem, layer: Double) throws -> [String: CloudValue] {
        let shared = SharedFieldPolicy.shared(item)
        var values: [CloudSchema.Key: CloudValue] = [
            .kind: .string(shared.kind.rawValue),
            .title: .string(shared.title),
            .createdAt: .double(shared.createdAt.timeIntervalSinceReferenceDate),
            .x: .double(shared.position.x),
            .y: .double(shared.position.y),
            .layer: .double(layer),
            .formatVersion: .int(Int64(Board(items: [shared]).requiredFormatVersion)),
        ]
        values[.parentID] = shared.parentID.map { .string($0.uuidString) }
        values[.folderX] = shared.folderPosition.map { .double($0.x) }
        values[.folderY] = shared.folderPosition.map { .double($0.y) }
        values[.fileName] = shared.fileName.map { .string($0) }
        values[.text] = shared.text.map { .string($0) }
        values[.caption] = shared.caption.map { .string($0) }
        values[.stickyColor] = shared.stickyColor.map { .string($0.rawValue) }
        values[.colorTag] = shared.colorTag.map { .string($0.rawValue) }
        values[.tag] = shared.tag.map { .string($0) }
        values[.checklist] = try shared.checklist.map { .data(try SyncJSON.encode($0)) }
        values[.imageMetadata] = try shared.imageMetadata.map { .data(try SyncJSON.encode($0)) }
        values[.link] = try shared.link.map { .data(try SyncJSON.encode($0)) }
        values[.reminder] = try shared.reminder.map { .data(try SyncJSON.encode($0)) }
        values[.music] = try shared.music.map { .data(try SyncJSON.encode($0)) }
        values[.attachments] = try shared.attachments.map { .data(try SyncJSON.encode($0)) }

        guard values.values.reduce(0, { $0 + payloadBytes(of: $1) }) <= maximumFieldBytes else {
            throw CardRecordMappingError.recordTooLarge(item.id)
        }
        return rawFields(values)
    }

    /// O cartão de um registro, na forma `SharedFieldPolicy.shared`. O `id` é o nome do registro.
    ///
    /// Registro de um app mais novo (versão do formato maior que `Board.currentFormatVersion`, ou um tipo de cartão ou uma cor que
    /// esta build não conhece) dá `.unsupported`, sem ler o resto: o que ele guarda além disso pode ter mudado de forma.
    /// - Throws: `CardRecordMappingError.invalidRecord` se o registro não é de cartão, o nome não é o `uuidString` do cartão, falta
    ///   `kind`, `title`, `createdAt`, `x` ou `y`, um campo tem o tipo errado, o JSON de um campo está ilegível, `folderX` e
    ///   `folderY` não vêm juntos ou um nome de arquivo sai de `Items/`.
    public static func card(from record: CloudRecord) throws -> CardDecoding {
        let id = try entityID(of: record, type: .card)
        let reader = FieldReader(record: record)

        if let version = try reader.int(.formatVersion), version > Int64(Board.currentFormatVersion) { return .unsupported }
        let rawKind = try reader.require(reader.string(.kind), .kind)
        guard let kind = ItemKind(rawValue: rawKind) else { return .unsupported }

        let title = try reader.require(reader.string(.title), .title)
        let createdAt = try reader.require(reader.double(.createdAt), .createdAt)
        let position = BoardPoint(x: try reader.require(reader.double(.x), .x), y: try reader.require(reader.double(.y), .y))

        var stickyColor: StickyColor?
        if let raw = try reader.string(.stickyColor) {
            guard let color = StickyColor(rawValue: raw) else { return .unsupported }
            stickyColor = color
        }
        var colorTag: TagColor?
        if let raw = try reader.string(.colorTag) {
            guard let color = TagColor(rawValue: raw) else { return .unsupported }
            colorTag = color
        }

        let folderPosition: BoardPoint?
        switch (try reader.double(.folderX), try reader.double(.folderY)) {
        case (let x?, let y?): folderPosition = BoardPoint(x: x, y: y)
        case (nil, nil): folderPosition = nil
        default: throw CardRecordMappingError.invalidRecord("folderX e folderY precisam vir juntos")
        }

        let fileName = try reader.string(.fileName)
        let attachments = try reader.json([NoteAttachment].self, .attachments)
        // O nome vem de outra pessoa e vira caminho em `Items/`: nada de sair da pasta.
        for name in (fileName.map { [$0] } ?? []) + (attachments ?? []).map(\.fileName) where !isSafeFileName(name) {
            throw CardRecordMappingError.invalidRecord("nome de arquivo fora de Items/: \(name)")
        }

        let item = BoardItem(
            id: id,
            kind: kind,
            title: title,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            parentID: try reader.uuid(.parentID),
            position: position,
            fileName: fileName,
            text: try reader.string(.text),
            caption: try reader.string(.caption),
            checklist: try reader.json(ChecklistDocument.self, .checklist),
            stickyColor: stickyColor,
            imageMetadata: try reader.json(ImageMetadata.self, .imageMetadata),
            tag: try reader.string(.tag),
            keySentences: nil,
            link: try reader.json(LinkInfo.self, .link),
            reminder: try reader.json(ReminderSnapshot.self, .reminder),
            music: try reader.json(MusicSnapshot.self, .music),
            colorTag: colorTag,
            attachments: attachments,
            folderPosition: folderPosition)
        return .card(SharedFieldPolicy.shared(item), layer: try reader.double(.layer))
    }

    // MARK: Texto livre

    /// Os campos do registro de um texto livre.
    public static func fields(for freeText: BoardFreeText) -> [String: CloudValue] {
        rawFields([
            .text: .string(freeText.text),
            .x: .double(freeText.position.x),
            .y: .double(freeText.position.y),
            .createdAt: .double(freeText.createdAt.timeIntervalSinceReferenceDate),
        ])
    }

    /// O texto livre de um registro. O `id` é o nome do registro.
    /// - Throws: `CardRecordMappingError.invalidRecord` se o registro não é de texto livre, o nome não é o `uuidString` dele ou
    ///   falta `text`, `x`, `y` ou `createdAt`, ou um deles tem o tipo errado.
    public static func freeText(from record: CloudRecord) throws -> BoardFreeText {
        let id = try entityID(of: record, type: .freeText)
        let reader = FieldReader(record: record)
        return BoardFreeText(
            id: id,
            text: try reader.require(reader.string(.text), .text),
            position: BoardPoint(x: try reader.require(reader.double(.x), .x), y: try reader.require(reader.double(.y), .y)),
            createdAt: Date(timeIntervalSinceReferenceDate: try reader.require(reader.double(.createdAt), .createdAt)))
    }

    // MARK: Mural

    /// Os campos do registro do mural: o nome e a versão do formato que o conteúdo exige (`Board.requiredFormatVersion`).
    public static func boardFields(name: String, board: Board) -> [String: CloudValue] {
        rawFields([
            .name: .string(name),
            .formatVersion: .int(Int64(board.requiredFormatVersion)),
        ])
    }

    /// O nome do mural, ou `nil` se o registro não é do mural ou não tem nome.
    public static func boardName(from record: CloudRecord) -> String? {
        guard record.type == CloudSchema.RecordType.mural.rawValue,
            case .string(let name)? = record.fields[CloudSchema.Key.name.rawValue]
        else { return nil }
        return name
    }

    // MARK: Arquivo de mídia

    /// Os campos do registro de um arquivo de `Items/`: o arquivo e o cartão a que ele pertence. O nome do registro é o do arquivo.
    public static func mediaFields(fileURL: URL, cardID: UUID) -> [String: CloudValue] {
        rawFields([
            .file: .asset(fileURL),
            .cardID: .string(cardID.uuidString),
        ])
    }

    /// O nome do arquivo (o do registro) e onde o iCloud o deixou, ou `nil` se o registro não é de arquivo de mídia, não traz o
    /// arquivo ou tem um nome que sairia de `Items/`: o nome vem de outra pessoa e vira caminho no disco.
    public static func mediaFile(from record: CloudRecord) -> (fileName: String, url: URL)? {
        guard record.type == CloudSchema.RecordType.mediaFile.rawValue,
            isSafeFileName(record.id.name),
            case .asset(let url)? = record.fields[CloudSchema.Key.file.rawValue]
        else { return nil }
        return (record.id.name, url)
    }

    // MARK: Interno

    /// Os campos com o nome que vai para o iCloud.
    private static func rawFields(_ values: [CloudSchema.Key: CloudValue]) -> [String: CloudValue] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    /// O que o campo pesa no limite do registro: o texto em UTF-8 e os bytes do dado. Números e arquivos não contam.
    private static func payloadBytes(of value: CloudValue) -> Int {
        switch value {
        case .string(let text): text.utf8.count
        case .data(let data): data.count
        case .int, .double, .asset: 0
        }
    }

    /// O id de um cartão ou texto livre, que é o nome do registro. Recusa registro de outro tipo e nome que não seja o `uuidString`
    /// do id: o nome de um registro distingue maiúsculas de minúsculas, então outro formato daria um segundo registro para o mesmo id.
    private static func entityID(of record: CloudRecord, type: CloudSchema.RecordType) throws -> UUID {
        guard record.type == type.rawValue else {
            throw CardRecordMappingError.invalidRecord("o registro é do tipo \(record.type), não \(type.rawValue)")
        }
        guard let id = UUID(uuidString: record.id.name), id.uuidString == record.id.name else {
            throw CardRecordMappingError.invalidRecord("o nome do registro não é um UUID: \(record.id.name)")
        }
        return id
    }

    /// Um nome de arquivo de `Items/`: um único componente, sem ocultos, `..`, `/` nem `:`. É a mesma regra do `BoardRepository`.
    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":") && name == (name as NSString).lastPathComponent
    }
}

/// Lê os campos de um registro com o tipo certo. Campo ausente dá `nil`; campo com outro tipo é erro, para um registro
/// malformado nunca virar um cartão com o campo calado.
private struct FieldReader {
    let record: CloudRecord

    func string(_ key: CloudSchema.Key) throws -> String? {
        guard let value = record.fields[key.rawValue] else { return nil }
        guard case .string(let text) = value else { throw wrongType(key) }
        return text
    }

    func int(_ key: CloudSchema.Key) throws -> Int64? {
        guard let value = record.fields[key.rawValue] else { return nil }
        guard case .int(let number) = value else { throw wrongType(key) }
        return number
    }

    func double(_ key: CloudSchema.Key) throws -> Double? {
        guard let value = record.fields[key.rawValue] else { return nil }
        guard case .double(let number) = value else { throw wrongType(key) }
        return number
    }

    func data(_ key: CloudSchema.Key) throws -> Data? {
        guard let value = record.fields[key.rawValue] else { return nil }
        guard case .data(let bytes) = value else { throw wrongType(key) }
        return bytes
    }

    /// Um UUID guardado como texto.
    func uuid(_ key: CloudSchema.Key) throws -> UUID? {
        guard let text = try string(key) else { return nil }
        guard let uuid = UUID(uuidString: text) else {
            throw CardRecordMappingError.invalidRecord("o campo \(key.rawValue) não é um UUID")
        }
        return uuid
    }

    /// Um valor guardado como JSON (ver `SyncJSON`).
    func json<Value: Decodable>(_ type: Value.Type, _ key: CloudSchema.Key) throws -> Value? {
        guard let bytes = try data(key) else { return nil }
        do {
            return try SyncJSON.decode(type, from: bytes)
        } catch {
            throw CardRecordMappingError.invalidRecord("o campo \(key.rawValue) tem JSON ilegível")
        }
    }

    /// O valor de um campo obrigatório.
    func require<Value>(_ value: Value?, _ key: CloudSchema.Key) throws -> Value {
        guard let value else { throw CardRecordMappingError.invalidRecord("falta o campo \(key.rawValue)") }
        return value
    }

    private func wrongType(_ key: CloudSchema.Key) -> CardRecordMappingError {
        .invalidRecord("o campo \(key.rawValue) tem o tipo errado")
    }
}
