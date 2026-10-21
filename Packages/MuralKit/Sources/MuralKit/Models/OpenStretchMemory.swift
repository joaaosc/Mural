import StretchText

/// Parágrafos que o leitor deixou abertos numa nota. Valem só para o texto em que
/// foram abertos: com o texto mudado, a nota volta toda dobrada.
public struct OpenStretchMemory: Codable, Equatable, Sendable {
    /// Mesmo hash de ``KeySentenceRecord``.
    public var sourceHash: String
    /// Em ordem de documento.
    public var openIDs: [StretchID]

    public init(source: String, openIDs: some Collection<StretchID>) {
        self.sourceHash = KeySentenceRecord.hash(of: source)
        self.openIDs = openIDs.sorted()
    }

    public func matches(_ source: String) -> Bool {
        sourceHash == KeySentenceRecord.hash(of: source)
    }
}
