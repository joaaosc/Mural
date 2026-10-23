import Foundation
import MuralKit
import SwiftUI

extension EnvironmentValues {
    /// Coordenador das capas de música da janela de mural aberta; `nil` fora de uma janela de mural.
    @Entry var musicArtworkCoordinator: MusicArtworkCoordinator? = nil
}

/// Um por janela de mural: baixa a capa dos cartões de música, grava na pasta de prévias e aplica ao mural.
@MainActor
final class MusicArtworkCoordinator {
    private let model: BoardModel
    private let files: LinkPreviewFiles
    private let fetcher: any MusicArtworkFetching

    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Cartões cuja busca falhou nesta janela; não são tentados de novo.
    private var failed: Set<UUID> = []

    init(model: BoardModel, files: LinkPreviewFiles, fetcher: any MusicArtworkFetching) {
        self.model = model
        self.files = files
        self.fetcher = fetcher
    }

    /// Baixa a capa dos cartões de música indicados que ainda não a têm na pasta e têm molde de endereço.
    /// Quem está em andamento ou já falhou nesta janela fica de fora.
    func request(_ itemIDs: [UUID]) {
        for id in itemIDs where tasks[id] == nil && !failed.contains(id) {
            guard let music = model.item(id: id)?.music, !hasArtworkOnDisk(music),
                let url = music.artworkURL(side: 600)
            else { continue }
            let fetcher = self.fetcher
            let files = self.files
            tasks[id] = Task { [weak self] in
                defer { self?.tasks[id] = nil }
                do {
                    let data = try await fetcher.fetchArtwork(at: url)
                    try Task.checkCancellation()
                    let name = try await Self.save(data, for: id, in: files)
                    self?.apply(name, to: id)
                } catch {
                    if !(error is CancellationError) { self?.failed.insert(id) }
                }
            }
        }
    }

    /// Grava a capa que já veio no arrasto, sem baixar.
    func store(_ imageData: Data, for itemID: UUID) {
        guard tasks[itemID] == nil else { return }
        let files = self.files
        tasks[itemID] = Task { [weak self] in
            defer { self?.tasks[itemID] = nil }
            guard let name = try? await Self.save(imageData, for: itemID, in: files) else { return }
            self?.apply(name, to: itemID)
        }
    }

    /// Cancela as buscas em andamento.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Espera as buscas e gravações pedidas até aqui terminarem.
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func hasArtworkOnDisk(_ music: MusicSnapshot) -> Bool {
        music.artworkFile.flatMap { files.existingURL(for: $0) } != nil
    }

    /// Relê o cartão: se sumiu, mudou de tipo ou já tem capa no disco, o arquivo novo é descartado.
    private func apply(_ name: String, to itemID: UUID) {
        guard var music = model.item(id: itemID)?.music, !hasArtworkOnDisk(music) else {
            if let url = files.url(for: name) { try? FileManager.default.removeItem(at: url) }
            return
        }
        music.artworkFile = name
        model.updateMusic(itemID, with: music)
    }

    @concurrent
    private nonisolated static func save(_ data: Data, for itemID: UUID, in files: LinkPreviewFiles) async throws -> String {
        guard let name = try files.store(imageData: data, iconData: nil, for: itemID).image else {
            throw URLError(.cannotDecodeContentData)
        }
        return name
    }
}
