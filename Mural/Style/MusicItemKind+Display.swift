import MuralKit
import SwiftUI

extension MusicItemKind {
    /// Nome do tipo, para a linha do cartão e para a acessibilidade.
    var displayName: String {
        switch self {
        case .album: "Álbum"
        case .song: "Música"
        case .playlist: "Playlist"
        case .station: "Estação"
        }
    }

    /// Símbolo do tipo, usado na linha do cartão e no lugar da capa que falta.
    var symbol: String {
        switch self {
        case .album: "square.stack"
        case .song: "music.note"
        case .playlist: "music.note.list"
        case .station: "dot.radiowaves.left.and.right"
        }
    }
}

extension MusicSnapshot {
    /// Linha curta sob o título: "Álbum · 12 faixas", "Música · 3:33", "Playlist" ou "Estação".
    var detailLine: String {
        let name = kind.displayName
        switch kind {
        case .album:
            guard let trackCount, trackCount >= 0 else { return name }
            return "\(name) · \(trackCount) \(trackCount == 1 ? "faixa" : "faixas")"
        case .song:
            // Acima do teto a conversão para inteiro poderia travar; mostra só o nome, como para valor inválido.
            guard let duration, duration >= 0, duration <= Self.maxDisplayedDuration else { return name }
            return "\(name) · \(Self.clock(duration))"
        case .playlist, .station:
            return name
        }
    }

    /// Teto (em segundos) da duração exibida; comparação falsa para NaN, então valor inválido também cai fora.
    static let maxDisplayedDuration: TimeInterval = 10_000_000

    /// Duração como "m:ss" ou, a partir de uma hora, "h:mm:ss".
    static func clock(_ duration: TimeInterval) -> String {
        let total = Int(min(max(duration, 0), maxDisplayedDuration).rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Ano de lançamento (os quatro primeiros dígitos de `releaseDate`), se houver.
    var releaseYear: String? {
        guard let prefix = releaseDate?.prefix(4), prefix.count == 4, prefix.allSatisfy(\.isASCII), prefix.allSatisfy(\.isNumber)
        else { return nil }
        return String(prefix)
    }
}

extension Color {
    /// Branco ou preto, o que se lê melhor sobre a cor `#rrggbb`; `nil` se o texto não for uma cor válida.
    static func readable(onHex text: String?) -> Color? {
        guard let hex = MusicSnapshot.normalizedHex(text), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        let red = Double(value >> 16 & 0xFF) / 255
        let green = Double(value >> 8 & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.55 ? .black : .white
    }

    /// Cor a partir de `#rrggbb` (com ou sem `#`); `nil` se o texto não for uma cor válida.
    init?(muralHex text: String?) {
        guard let hex = MusicSnapshot.normalizedHex(text), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double(value >> 16 & 0xFF) / 255,
            green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
