import Foundation
import MuralKit

/// Guarda a foto reduzida dos contatos recém-criados na pasta de prévias do mural e liga o arquivo ao cartão
/// (`ContactSnapshot.thumbnailFile`). A foto é local: não vai na cópia para outras pessoas nem no pacote.
///
/// Um por sessão de janela (`BoardWindowSession.contactThumbnails`): a sessão o cancela ao fechar, e quem entrega um contato a um
/// mural fechado espera `waitUntilIdle()` antes de fechar a sessão avulsa.
@MainActor
final class ContactThumbnailStore {
    private weak var model: BoardModel?
    private let files: LinkPreviewFiles
    /// Diz se a sessão ainda aceita gravar; falso depois de fechada.
    private let isActive: @MainActor () -> Bool
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(model: BoardModel, files: LinkPreviewFiles, isActive: @escaping @MainActor () -> Bool = { true }) {
        self.model = model
        self.files = files
        self.isActive = isActive
    }

    /// Grava a foto de cada cartão criado a partir do rascunho de mesma `dedupeKey`. Rascunho sem foto, ou cuja foto o
    /// ImageIO não lê, deixa o cartão com as iniciais.
    func store(_ drafts: [ContactDraft], for created: [BoardItem]) {
        for item in created {
            guard let key = item.contact?.dedupeKey,
                let data = drafts.first(where: { $0.snapshot.dedupeKey == key && $0.thumbnailData != nil })?.thumbnailData
            else { continue }
            store(data, for: item.id)
        }
    }

    /// Cancela as gravações em andamento.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Espera as gravações pedidas até aqui terminarem.
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
            // Uma tarefa cancelada pode não ter limpado a própria entrada.
            if let key = tasks.first(where: { $0.value == task })?.key { tasks[key] = nil }
        }
    }

    private func store(_ data: Data, for itemID: UUID) {
        guard tasks[itemID] == nil else { return }
        let files = self.files
        // Captura forte de propósito: o ciclo se desfaz quando a tarefa termina ou o armazém é cancelado.
        tasks[itemID] = Task {
            defer { self.tasks[itemID] = nil }
            guard let name = try? await Self.save(data, for: itemID, in: files) else { return }
            self.apply(name, to: itemID)
        }
    }

    /// Relê o cartão: com o mural fechado, a sessão cancelada, o modelo ou o cartão sumidos, o arquivo novo é descartado.
    private func apply(_ name: String, to itemID: UUID) {
        guard !Task.isCancelled, isActive(), let model, model.setContactThumbnail(itemID, file: name) else {
            if let url = files.url(for: name) { try? FileManager.default.removeItem(at: url) }
            return
        }
    }

    @concurrent
    private nonisolated static func save(_ data: Data, for itemID: UUID, in files: LinkPreviewFiles) async throws -> String {
        guard let name = try files.store(imageData: data, iconData: nil, for: itemID).image else {
            throw URLError(.cannotDecodeContentData)
        }
        return name
    }
}
