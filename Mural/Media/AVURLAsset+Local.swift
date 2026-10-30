import AVFoundation

extension AVURLAsset {
    /// Asset de um arquivo do mural. Proíbe referências externas: um vídeo de um .mural alheio
    /// (HLS, `.mov` com referência) não pode puxar mídia de fora do arquivo.
    nonisolated static func local(_ url: URL) -> AVURLAsset {
        AVURLAsset(
            url: url,
            options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
    }
}
