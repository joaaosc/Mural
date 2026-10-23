/// Tipo de conteúdo que um cartão do mural representa.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// Fotografia ou ilustração (jpeg, png, heic...).
    case image
    /// Arquivo de vídeo (mov, mp4...).
    case video
    /// Nota de texto longa (txt, md ou texto colado).
    case text
    /// Documento PDF.
    case pdf
    /// Lista de itens marcáveis, organizada em seções.
    case checklist
    /// Post-it: texto curto sobre fundo colorido.
    case sticky
    /// Endereço da web, com prévia buscada da própria página.
    case link
    /// Lembrete do app Lembretes, guardado como o último estado conhecido.
    case reminder
    /// Álbum, faixa, playlist ou estação do Apple Music, guardado como o último estado conhecido.
    case music
    /// Pasta que agrupa outros cartões (uma coleção).
    case folder

    /// Indica se o cartão guarda um arquivo copiado para a pasta de itens.
    public var storesFile: Bool {
        switch self {
        case .image, .video, .pdf: true
        case .text, .checklist, .sticky, .link, .reminder, .music, .folder: false
        }
    }
}
