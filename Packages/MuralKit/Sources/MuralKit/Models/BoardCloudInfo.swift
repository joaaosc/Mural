import Foundation

/// Onde um mural compartilhado vive no iCloud e o que esta pessoa pode fazer nele. Mural só local não tem.
///
/// Os valores de `Database` e de `Permission` são gravados no `manifest.json` pelo nome do caso. Um caso novo em qualquer um
/// dos dois exige subir `BoardManifest.currentSchemaVersion`: é a versão maior que faz uma build antiga recusar o mural, em vez
/// de abri-lo, não entender o valor e gravar por cima.
public struct BoardCloudInfo: Codable, Equatable, Sendable {
    /// `private`: o mural é desta pessoa (zona no banco privado dela); `shared`: de outra pessoa, recebido por convite.
    public enum Database: String, Codable, Sendable {
        case `private`
        case shared
    }

    /// `owner`: quem criou e compartilhou o mural; `readWrite`: quem pode editar; `readOnly`: quem só pode ver.
    public enum Permission: String, Codable, Sendable {
        case owner
        case readWrite
        case readOnly
    }

    public var database: Database
    /// Nome da zona do mural no iCloud.
    public var zoneName: String
    /// O dono da zona como o CloudKit o identifica (`CKRecordZone.ID.ownerName`).
    public var zoneOwnerName: String
    /// Nome do dono para mostrar ("de Ana"); `nil` no próprio dono.
    public var ownerDisplayName: String?
    public var permission: Permission

    /// `true` quando esta pessoa só pode ver o mural.
    public var isReadOnly: Bool { permission == .readOnly }

    public init(
        database: Database,
        zoneName: String,
        zoneOwnerName: String,
        ownerDisplayName: String? = nil,
        permission: Permission
    ) {
        self.database = database
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.ownerDisplayName = ownerDisplayName
        self.permission = permission
    }
}
