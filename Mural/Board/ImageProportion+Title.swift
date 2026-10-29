import MuralKit

extension ImageProportion {
    /// Nome no menu "Tamanho" de uma foto.
    var menuTitle: String {
        switch self {
        case .original: "Foto inteira"
        case .fixed(width: 1, height: 1): "Quadrada (1:1)"
        case .fixed(let width, let height) where width > height && width == 16: "Panorâmica (\(width):\(height))"
        case .fixed(let width, let height) where height > width && height == 16: "Vertical (\(width):\(height))"
        case .fixed(let width, let height) where width > height: "Paisagem (\(width):\(height))"
        case .fixed(let width, let height): "Retrato (\(width):\(height))"
        }
    }

    /// Texto curto da etiqueta que aparece junto do canto durante o encaixe.
    var badgeTitle: String {
        switch self {
        case .original: "Foto inteira"
        case .fixed(let width, let height): "\(width):\(height)"
        }
    }
}
