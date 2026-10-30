import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Imagens geradas em memória pelos testes: nenhum arquivo de mídia é versionado.
enum TestImages {
    /// PNG com canal alfa. Com `transparent`, o quadrante superior direito fica totalmente transparente; sem
    /// ele, todos os pixels são opacos (como numa captura de tela salva em RGBA).
    static func png(width: Int, height: Int, transparent: Bool = false) throws -> Data {
        try encode(try image(width: width, height: height, transparent: transparent), as: .png)
    }

    /// JPEG; `orientation` grava a orientação EXIF (6 = girar 90° no sentido horário).
    static func jpeg(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        try encode(try image(width: width, height: height, transparent: false), as: .jpeg, orientation: orientation)
    }

    /// PNG em tons de cinza, de uma cor só. Comprime a quase nada e o contexto de desenho gasta 1 byte por pixel,
    /// então serve para imagens de dezenas de milhões de pixels.
    static func grayPNG(width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try encode(try #require(context.makeImage()), as: .png)
    }

    /// Largura e altura em pixels gravadas no arquivo, sem aplicar a orientação.
    static func size(of data: Data) -> (width: Int, height: Int)? {
        guard let properties = properties(of: data), let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Identificador do formato (`public.jpeg`, `public.png`...).
    static func typeIdentifier(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    /// O arquivo declara canal alfa.
    static func hasAlpha(_ data: Data) -> Bool {
        properties(of: data)?[kCGImagePropertyHasAlpha] as? Bool ?? false
    }

    private static func properties(of data: Data) -> [CFString: Any]? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    }

    private static func image(width: Int, height: Int, transparent: Bool) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        if transparent {
            context.clear(CGRect(x: width / 2, y: height / 2, width: width - width / 2, height: height - height / 2))
        }
        return try #require(context.makeImage())
    }

    private static func encode(_ image: CGImage, as type: UTType, orientation: Int? = nil) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

/// Espera a condição ficar verdadeira, consultando a cada 5 ms; registra uma falha se passar de `timeout`.
func waitUntil(
    _ description: String, timeout: Duration = .seconds(10), sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while await !condition() {
        if clock.now >= deadline {
            Issue.record("Tempo esgotado esperando: \(description)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Espera de lote que só o teste libera: cada `sleep()` fica parado até `releaseAll()`. Cancelar a tarefa encerra a espera
/// com `CancellationError`, como `Task.sleep`. Assim os testes de lote não dependem da velocidade da máquina.
actor ManualSleeper {
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    /// Cancelamento que chegou antes de a espera começar (a tarefa já estava cancelada).
    private var cancelledEarly: Set<UUID> = []

    var waitingCount: Int { waiters.count }

    func sleep() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if cancelledEarly.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func releaseAll() {
        let released = waiters.values
        waiters.removeAll()
        for continuation in released { continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledEarly.insert(id)
        }
    }
}
