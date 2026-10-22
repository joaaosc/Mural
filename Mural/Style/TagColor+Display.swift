import AppKit
import MuralKit
import SwiftUI

extension TagColor {
    /// Nome da cor para o menu e a acessibilidade.
    var displayName: String {
        switch self {
        case .red: "Vermelho"
        case .orange: "Laranja"
        case .yellow: "Amarelo"
        case .green: "Verde"
        case .blue: "Azul"
        case .purple: "Roxo"
        case .gray: "Cinza"
        }
    }

    /// Cor do sistema, que acompanha o modo claro e o escuro.
    var color: Color {
        switch self {
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .gray: Color(nsColor: .systemGray)
        }
    }
}
