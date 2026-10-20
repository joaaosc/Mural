/// Falhas ao ler o mural gravado.
public enum BoardStoreError: Error, Sendable {
    case corruptedFile(underlying: String)
}
