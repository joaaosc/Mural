import MuralKit
import SwiftUI

/// Submenu "Tamanho" do menu de contexto de um post-it ou de um texto livre solto no mural: os tamanhos quadrados predefinidos
/// pelo domínio (`BoardLayout.stickyPresetSides`, `BoardLayout.freeTextPresetSides`) e a volta ao tamanho padrão. É a alternativa
/// ao arrasto do canto, que não se faz pelo teclado nem pela leitura de tela.
struct BoardSizeMenu: View {
    /// Lados das predefinições, do menor ao maior. Os nomes (`names`) seguem a mesma ordem.
    let sides: [Double]
    /// Se o elemento já está no tamanho padrão: então "Tamanho padrão" fica desligado.
    let isStandard: Bool
    /// Ícone do título do submenu, para os menus em que os outros itens também têm ícone.
    var systemImage: String? = nil
    /// Recebe o tamanho escolhido; `nil` devolve o elemento ao tamanho padrão.
    var onSelect: (BoardSize?) -> Void

    private static let names = ["Pequeno", "Médio", "Grande", "Muito grande"]

    var body: some View {
        Menu {
            ForEach(Array(sides.enumerated()), id: \.offset) { index, side in
                Button(Self.name(at: index, side: side)) {
                    onSelect(BoardSize(width: side, height: side))
                }
            }
            Divider()
            Button("Tamanho padrão") { onSelect(nil) }
                .disabled(isStandard)
        } label: {
            if let systemImage {
                Label("Tamanho", systemImage: systemImage)
            } else {
                Text("Tamanho")
            }
        }
    }

    /// Uma predefinição a mais no domínio, sem nome aqui, aparece pelo lado em vez de sumir.
    private static func name(at index: Int, side: Double) -> String {
        names.indices.contains(index) ? names[index] : "\(Int(side)) pt"
    }
}
