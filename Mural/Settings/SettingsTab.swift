/// As abas da janela de Ajustes.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    /// Abrir ao iniciar sessão e sair do app.
    case general
    /// O painel da barra de menus: o atalho e o lugar onde ele abre.
    case panel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Geral"
        case .panel: "Painel"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .panel: "menubar.rectangle"
        }
    }
}
