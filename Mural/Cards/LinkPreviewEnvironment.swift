import MuralKit
import SwiftUI

extension EnvironmentValues {
    /// Pasta das imagens e dos ícones de prévia dos links do mural aberto; `nil` fora de uma janela de mural.
    @Entry var linkPreviewFiles: LinkPreviewFiles? = nil
}
