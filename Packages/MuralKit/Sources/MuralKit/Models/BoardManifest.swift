import Foundation

/// Metadados e revisões do pacote de um mural.
///
/// Um mural sem `cloud` continua gravado exatamente como antes (`schemaVersion` 1, sem a chave nova), para as builds 0.9.x
/// seguirem abrindo os murais que não são compartilhados. Só o mural compartilhado exige a versão 2, e as builds antigas já o
/// recusam por `BoardRepositoryError.futureManifestSchema`: nenhuma delas o abre e depois grava por cima, sem o `cloud`.
public struct BoardManifest: Codable, Equatable, Sendable {
    /// A versão mais nova do manifest que esta build lê. Uma build recusa abrir um mural de versão maior que a sua
    /// (`BoardRepositoryError.futureManifestSchema`).
    /// - 1: nome, datas e revisões.
    /// - 2: mural compartilhado pelo iCloud (`cloud`).
    public static let currentSchemaVersion = 2

    /// Versão do formato gravada no manifest. Quem monta o manifest sem pedir uma versão (e quem põe ou tira o `cloud`)
    /// fica com `requiredSchemaVersion`.
    public var schemaVersion: Int
    public var id: BoardID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var contentRevision: Int
    public var workspaceRevision: Int
    /// Onde o mural vive no iCloud e o que esta pessoa pode fazer nele; `nil` num mural só deste Mac. Pôr ou tirar o valor
    /// leva `schemaVersion` para a versão que ele exige.
    public var cloud: BoardCloudInfo? {
        didSet { schemaVersion = requiredSchemaVersion }
    }

    /// - Parameter schemaVersion: `nil` vale `requiredSchemaVersion`. Passar um número serve para reproduzir um manifest
    ///   gravado por outra build.
    public init(
        id: BoardID,
        name: String = "Mural",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        contentRevision: Int = 0,
        workspaceRevision: Int = 0,
        cloud: BoardCloudInfo? = nil,
        schemaVersion: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentRevision = contentRevision
        self.workspaceRevision = workspaceRevision
        self.cloud = cloud
        self.schemaVersion = schemaVersion ?? Self.minimumSchemaVersion(for: cloud)
    }

    /// A menor versão do manifest que guarda este conteúdo sem perder nada: 1 sem `cloud` e 2 com ele. Cada versão nova
    /// do formato precisa de uma regra aqui.
    public var requiredSchemaVersion: Int { Self.minimumSchemaVersion(for: cloud) }

    private static func minimumSchemaVersion(for cloud: BoardCloudInfo?) -> Int {
        cloud == nil ? 1 : 2
    }

    /// Alias semântico para callers que chamam a versão de formato.
    public var formatVersion: Int {
        get { schemaVersion }
        set { schemaVersion = newValue }
    }

    public var displayName: String {
        get { name }
        set { name = newValue }
    }
}
