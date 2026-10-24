import Foundation

// O registro como o iCloud o guarda, sem depender do CloudKit. O motor de verdade converte de e para `CKRecord`, e o iCloud falso
// dos testes trabalha direto com estes tipos: assim a regra de sincronização (o que vira campo, o que é lido de volta) fica
// testável sem conta iCloud, sem rede e sem simulador.

/// A zona de um mural no iCloud: o par nome e dono que o CloudKit usa (`CKRecordZone.ID`).
public struct CloudZoneID: Hashable, Codable, Sendable {
    /// O dono de uma zona do banco privado da própria pessoa (`CKCurrentUserDefaultName`).
    public static let defaultOwnerName = "__defaultOwner__"

    public var name: String
    public var ownerName: String

    public init(name: String, ownerName: String = CloudZoneID.defaultOwnerName) {
        self.name = name
        self.ownerName = ownerName
    }
}

/// O identificador de um registro: a zona e o nome dentro dela (`CKRecord.ID`).
public struct CloudRecordID: Hashable, Codable, Sendable {
    public var zone: CloudZoneID
    public var name: String

    public init(zone: CloudZoneID, name: String) {
        self.zone = zone
        self.name = name
    }
}

/// O valor de um campo. Só os tipos que o Mural usa; data não tem caso próprio de propósito (ver `CardRecordMapping`).
public enum CloudValue: Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case data(Data)
    /// Um arquivo, que no iCloud fica fora do limite de tamanho do registro.
    case asset(URL)
}

/// Um registro de uma zona: o tipo, os campos e o que o servidor acrescenta.
public struct CloudRecord: Hashable, Sendable {
    public var id: CloudRecordID
    public var type: String
    public var fields: [String: CloudValue]
    /// Quem criou o registro (o nome do registro de usuário no CloudKit); nil antes de ir ao servidor.
    public var creatorUserRecordName: String?
    /// Campos de sistema do registro, opacos: o motor de verdade guarda aqui o arquivamento do `CKRecord` (`encodeSystemFields`),
    /// que leva a marca de alteração do servidor; o iCloud falso guarda a sua marca. Nil num registro que nunca foi ao servidor.
    public var systemFields: Data?

    public init(
        id: CloudRecordID,
        type: String,
        fields: [String: CloudValue] = [:],
        creatorUserRecordName: String? = nil,
        systemFields: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.fields = fields
        self.creatorUserRecordName = creatorUserRecordName
        self.systemFields = systemFields
    }
}
