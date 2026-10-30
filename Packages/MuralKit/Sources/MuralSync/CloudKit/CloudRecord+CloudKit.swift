import CloudKit
import Foundation

// A ponte entre o modelo neutro do `MuralSync` (`CloudRecord`) e o CloudKit (`CKRecord`). Só converte tipos: o que enviar, como juntar
// e o que apagar já está decidido no `SyncCore` e no `BoardSyncCoordinator`.

/// Os erros ao converter entre `CKRecord` e `CloudRecord`.
public enum CloudKitConversionError: Error, Equatable, Sendable {
    /// Uma chave que o Mural conhece chegou com um tipo que ele não usa (data, referência, lista, localização).
    case unsupportedFieldType(key: String)
    /// Um `CKAsset` sem `fileURL`: o arquivo ainda não está no disco.
    case assetWithoutFile(key: String)
    /// Os campos de sistema guardados não puderam ser lidos de volta.
    case invalidSystemFields
}

// MARK: Zona e identificador

extension CloudZoneID {
    public init(_ zoneID: CKRecordZone.ID) {
        self.init(name: zoneID.zoneName, ownerName: zoneID.ownerName)
    }

    /// A zona no CloudKit, com o dono como veio: o mesmo registro tem `ownerName` diferente do lado do dono
    /// (`CKCurrentUserDefaultName`) e do lado do convidado (o nome do dono), então o dono nunca é trocado.
    public var ckZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: ownerName)
    }
}

extension CloudRecordID {
    public init(_ recordID: CKRecord.ID) {
        self.init(zone: CloudZoneID(recordID.zoneID), name: recordID.recordName)
    }

    public var ckRecordID: CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zone.ckZoneID)
    }
}

// MARK: Valores

extension CloudValue {
    /// O valor de um campo de chave conhecida, fiel ao tipo que veio. Texto, dado e arquivo passam como são; um número vira `.int` ou
    /// `.double` pela tabela de chaves (`CloudSchema.Key.numberKind`), porque o CloudKit devolve um `NSNumber` e o tipo do valor não
    /// é de confiança. Um valor de tipo errado para a chave (texto onde se espera número) passa como veio: quem o recusa é o
    /// `CardRecordMapping`, e o `SyncCore` anota o registro como ilegível sem derrubar a leva.
    /// - Throws: `CloudKitConversionError.unsupportedFieldType` se o valor não é texto, número, dado nem arquivo, e
    ///   `.assetWithoutFile` se o arquivo não tem `fileURL`.
    init(_ value: any CKRecordValue, key: CloudSchema.Key) throws {
        switch value {
        case let text as String: self = .string(text)
        case let data as Data: self = .data(data)
        case let asset as CKAsset: self = try Self.asset(fileURL: asset.fileURL, key: key.rawValue)
        case let number as NSNumber: self = Self.number(number, key: key)
        default: throw CloudKitConversionError.unsupportedFieldType(key: key.rawValue)
        }
    }

    static func asset(fileURL: URL?, key: String) throws -> CloudValue {
        guard let fileURL else { throw CloudKitConversionError.assetWithoutFile(key: key) }
        return .asset(fileURL)
    }

    private static func number(_ number: NSNumber, key: CloudSchema.Key) -> CloudValue {
        let isFloatingPoint = ["f", "d"].contains(String(cString: number.objCType))
        switch key.numberKind {
        case .integer:
            // Um inteiro guardado como Double (11.0) é o mesmo inteiro; com parte fracionária o valor passa como veio.
            if isFloatingPoint {
                guard let exact = Int64(exactly: number.doubleValue) else { return .double(number.doubleValue) }
                return .int(exact)
            }
            return .int(number.int64Value)
        case .floatingPoint:
            return .double(number.doubleValue)
        case nil:
            return isFloatingPoint ? .double(number.doubleValue) : .int(number.int64Value)
        }
    }

    /// O valor como o CloudKit o guarda.
    var ckValue: any CKRecordValue {
        switch self {
        case .string(let text): return text as NSString
        case .int(let number): return NSNumber(value: number)
        case .double(let number): return NSNumber(value: number)
        case .data(let data): return data as NSData
        case .asset(let url): return CKAsset(fileURL: url)
        }
    }
}

extension CloudSchema.Key {
    enum NumberKind {
        case integer
        case floatingPoint
    }

    /// O tipo numérico da chave, ou `nil` se a chave não guarda número. É a tabela que desempata o `NSNumber` do CloudKit: a versão
    /// do formato é inteira; datas (`createdAt`), posições, camada, posição na pasta e tamanho são Double.
    var numberKind: NumberKind? {
        switch self {
        case .formatVersion: .integer
        case .createdAt, .x, .y, .layer, .folderX, .folderY, .width, .height: .floatingPoint
        case .kind, .title, .parentID, .fileName, .text, .caption, .stickyColor, .colorTag, .tag, .checklist, .imageMetadata, .link,
            .reminder, .music, .contact, .attachments, .name, .file, .cardID:
            nil
        }
    }
}

extension CloudSchema.RecordType {
    /// As chaves que um registro deste tipo pode ter. O envio usa a lista para apagar no iCloud o campo que o registro daqui perdeu.
    var keys: Set<CloudSchema.Key> {
        switch self {
        case .mural:
            [.name, .formatVersion]
        case .card:
            [
                .kind, .title, .createdAt, .parentID, .x, .y, .layer, .folderX, .folderY, .fileName, .text, .caption, .stickyColor,
                .colorTag, .tag, .checklist, .imageMetadata, .link, .reminder, .music, .contact, .attachments, .width, .height,
                .formatVersion,
            ]
        case .freeText:
            [.text, .x, .y, .createdAt, .width, .height, .formatVersion]
        case .mediaFile:
            [.file, .cardID]
        }
    }
}

// MARK: Registro

extension CloudRecord {
    /// O registro do CloudKit como o modelo neutro: tipo, identificador, quem o criou, os campos de chave conhecida e os campos de
    /// sistema arquivados (`systemFields`, com a marca de alteração do servidor).
    ///
    /// Chave que o `CloudSchema.Key` não conhece fica de fora: é de um app mais novo e este não a entende nem a apaga. O `fileURL` de
    /// um `CKAsset` buscado só vale durante o evento que o trouxe: quem recebe copia o arquivo antes de o evento terminar.
    /// - Throws: `CloudKitConversionError` se uma chave conhecida tem tipo que o Mural não usa ou um arquivo sem `fileURL`.
    public init(_ record: CKRecord) throws {
        var fields: [String: CloudValue] = [:]
        for name in record.allKeys() {
            guard let key = CloudSchema.Key(rawValue: name), let value = record.object(forKey: name) else { continue }
            fields[name] = try CloudValue(value, key: key)
        }
        self.init(
            id: CloudRecordID(record.recordID),
            type: record.recordType,
            fields: fields,
            creatorUserRecordName: record.creatorUserRecordID?.recordName,
            systemFields: Self.archivedSystemFields(of: record))
    }

    /// O registro para enviar ao CloudKit. Com `systemFields`, parte do registro desarquivado (a marca de alteração do servidor vai
    /// junto, e o servidor detecta o conflito); sem eles, de um registro novo.
    ///
    /// Os campos de sistema não levam as chaves do registro, então só as chaves deste `CloudRecord` entram no envio: uma chave que um
    /// app mais novo gravou fica intacta no iCloud. A exceção é o campo que o registro daqui perdeu (um cartão sem legenda deixa de ter
    /// `caption`): no CloudKit, campo omitido não apaga o que o servidor já tem, então as chaves do tipo de registro que faltam em
    /// `fields` são gravadas como `nil`. Registro novo não tem o que apagar.
    /// - Throws: `CloudKitConversionError.invalidSystemFields` se os campos de sistema guardados não são legíveis.
    public func makeCKRecord() throws -> CKRecord {
        let record: CKRecord
        var removable = Set<CloudSchema.Key>()
        if let systemFields {
            record = try Self.unarchivedRecord(from: systemFields)
            removable = CloudSchema.RecordType(rawValue: type)?.keys ?? []
            removable.formUnion(record.allKeys().compactMap { CloudSchema.Key(rawValue: $0) })
        } else {
            record = CKRecord(recordType: type, recordID: id.ckRecordID)
        }
        for (name, value) in fields {
            record.setObject(value.ckValue, forKey: name)
        }
        for key in removable where fields[key.rawValue] == nil {
            record.setObject(nil, forKey: key.rawValue)
        }
        return record
    }

    private static func archivedSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func unarchivedRecord(from data: Data) throws -> CKRecord {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { throw CloudKitConversionError.invalidSystemFields }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver) else { throw CloudKitConversionError.invalidSystemFields }
        return record
    }
}
