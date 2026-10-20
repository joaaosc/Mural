import Foundation

/// Cor RGB em 0...1, sem depender de SwiftUI.
public struct PaletteColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Dados exibidos ao lado de uma imagem no detalhe.
public struct ImageMetadata: Codable, Hashable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var fileSizeBytes: Int
    public var colorProfile: String?
    /// Cores dominantes, da mais clara para a mais escura.
    public var palette: [PaletteColor]

    public init(pixelWidth: Int, pixelHeight: Int, fileSizeBytes: Int, colorProfile: String?, palette: [PaletteColor]) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSizeBytes = fileSizeBytes
        self.colorProfile = colorProfile
        self.palette = palette
    }

    public var resolutionText: String { "\(pixelWidth) × \(pixelHeight)" }

    public var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }
}
