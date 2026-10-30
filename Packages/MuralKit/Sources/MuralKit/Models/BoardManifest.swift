import Foundation

/// Metadados e revisões do pacote de um mural.
///
/// Um mural sem `cloud` continua gravado exatamente como antes (`schemaVersion` 1, sem a chave nova), para as builds 0.9.x
/// seguirem abrindo os murais que não são compartilhados. Só o mural compartilhado exige a versão 2, e as builds antigas já o
/// recusam por `BoardRepositoryError.futureManifestSchema`: nenhuma delas o abre e depois grava por cima, sem o `cloud`.
/// A cópia para enviar a outras pessoas, quando leva as prévias dos links, exige a versão 3 (`previewsIncluded`); o mural
/// importado dela volta à versão 1, porque as prévias vão para a pasta própria deste Mac.
public struct BoardManifest: Codable, Equatable, Sendable {
    /// A versão mais nova do manifest que esta build lê. Uma build recusa abrir um mural de versão maior que a sua
    /// (`BoardRepositoryError.futureManifestSchema`).
    /// - 1: nome, datas e revisões.
    /// - 2: mural compartilhado pelo iCloud (`cloud`).
    /// - 3: pacote de cópia com a pasta `Previews` (`previewsIncluded`).
    public static let currentSchemaVersion = 3

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
    /// `true` num pacote de cópia que leva as imagens das prévias de link e das capas de música na pasta `Previews`; `nil` nos
    /// demais (a chave nem é gravada). Pôr ou tirar o valor leva `schemaVersion` para a versão que ele exige.
    public var previewsIncluded: Bool? {
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
        previewsIncluded: Bool? = nil,
        schemaVersion: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentRevision = contentRevision
        self.workspaceRevision = workspaceRevision
        self.cloud = cloud
        self.previewsIncluded = previewsIncluded
        self.schemaVersion = schemaVersion ?? Self.minimumSchemaVersion(for: cloud, previewsIncluded: previewsIncluded)
    }

    /// A menor versão do manifest que guarda este conteúdo sem perder nada: 1 sem `cloud`, 2 com ele e 3 com as prévias
    /// incluídas. Cada versão nova do formato precisa de uma regra aqui.
    public var requiredSchemaVersion: Int { Self.minimumSchemaVersion(for: cloud, previewsIncluded: previewsIncluded) }

    private static func minimumSchemaVersion(for cloud: BoardCloudInfo?, previewsIncluded: Bool?) -> Int {
        if previewsIncluded == true { return 3 }
        return cloud == nil ? 1 : 2
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
