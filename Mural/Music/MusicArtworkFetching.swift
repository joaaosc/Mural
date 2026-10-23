import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Por que o download de uma capa não deu nada.
nonisolated enum MusicArtworkFetchError: Error, Equatable {
    /// O endereço não é `http` nem `https`.
    case unsupportedAddress
    /// O servidor respondeu com um status fora de 200–299.
    case badStatus(Int)
}

/// Baixa a imagem da capa de um item do Apple Music.
nonisolated protocol MusicArtworkFetching: Sendable {
    func fetchArtwork(at url: URL) async throws -> Data
}

/// Baixa a capa na rede, até 8 MB, numa sessão efêmera própria (sem cookies, credenciais nem cache).
nonisolated struct SystemMusicArtworkFetcher: MusicArtworkFetching {
    /// Bytes de uma capa, no máximo.
    static let byteLimit = 8 * 1024 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func fetchArtwork(at url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw MusicArtworkFetchError.unsupportedAddress
        }
        var request = URLRequest(url: url)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let output = try await BoundedDownload.load(request, using: Self.session) { response in
            guard (200..<300).contains(response.statusCode) else { throw MusicArtworkFetchError.badStatus(response.statusCode) }
            return BoundedDownload.Plan(maximumBytes: Self.byteLimit, failsAboveMaximum: true)
        }
        return output.data
    }
}

/// Buscador dos testes de interface: sem rede, devolve um PNG 64×64 de uma cor que depende do endereço.
nonisolated struct FixtureMusicArtworkFetcher: MusicArtworkFetching {
    func fetchArtwork(at url: URL) async throws -> Data {
        let hash = url.absoluteString.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        let red = Double(hash & 0xFF) / 255
        let green = Double((hash >> 8) & 0xFF) / 255
        let blue = Double((hash >> 16) & 0xFF) / 255
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw URLError(.cannotDecodeContentData) }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let output = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw URLError(.cannotDecodeContentData) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw URLError(.cannotDecodeContentData) }
        return output as Data
    }
}
