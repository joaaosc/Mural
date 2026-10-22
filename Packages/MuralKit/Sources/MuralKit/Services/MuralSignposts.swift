import os

/// Intervalos para medir no Instruments (os_signpost): gravação, importação e
/// restauração. Subsistema `com.joaocosta.Mural`; filtre por categoria.
public enum MuralSignposts {
    public static let persistence = OSSignposter(subsystem: "com.joaocosta.Mural", category: "Persistência")
    public static let importing = OSSignposter(subsystem: "com.joaocosta.Mural", category: "Importação")
    public static let restoration = OSSignposter(subsystem: "com.joaocosta.Mural", category: "Restauração")
}
