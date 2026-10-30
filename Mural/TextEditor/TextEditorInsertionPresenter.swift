import MuralKit
import PhotosUI
import SwiftUI

/// Abre o que cada item do botão Inserir pede e põe o resultado no documento: a folha de música, de lembretes ou de link, o seletor
/// de fotos ou o painel do Finder. `request` é o item aberto; volta a `nil` quando ele fecha.
struct TextEditorInsertionPresenter: ViewModifier {
    let document: TextEditorDocument
    @Binding var request: TextEditorInsertion?

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetRequest) { insertion in
                switch insertion {
                case .music:
                    MusicSearchSheet(provider: MusicCenter.shared) { document.insertCards([.music($0)]) }
                case .reminder:
                    ReminderPickerSheet(provider: RemindersCenter.shared) { snapshots in
                        document.insertCards(snapshots.map { .reminder($0) })
                    }
                case .link:
                    LinkInsertSheet { urls in
                        _ = document.paste(.links(urls.map { LinkDraft(url: $0) }))
                    }
                case .photos, .contact, .finder:
                    EmptyView()
                }
            }
            .photosPicker(isPresented: isPresented(.photos), selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in insertPhotos(items) }
            .fileImporter(
                isPresented: isPickingFile,
                allowedContentTypes: request == .contact ? TextEditorFileInsertion.contactTypes : TextEditorFileInsertion.allowedTypes,
                allowsMultipleSelection: true, onCompletion: insertFiles
            )
            .fileDialogMessage(request == .contact ? "Escolha um contato em formato vCard (.vcf)." : "Escolha imagens ou contatos (.vcf).")
            .alert(
                "Não foi possível inserir", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }),
                presenting: problem
            ) { _ in
                Button("OK") {}
            } message: { problem in
                Text(problem)
            }
    }

    // MARK: Ligações

    private var sheetRequest: Binding<TextEditorInsertion?> {
        Binding(get: { request?.usesSheet == true ? request : nil }, set: { request = $0 })
    }

    private func isPresented(_ insertion: TextEditorInsertion) -> Binding<Bool> {
        Binding(get: { request == insertion }, set: { if !$0 { request = nil } })
    }

    private var isPickingFile: Binding<Bool> {
        Binding(get: { request == .contact || request == .finder }, set: { if !$0 { request = nil } })
    }

    // MARK: Inserir

    private func insertFiles(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        Task {
            let reading = await TextEditorFileInsertion.read(urls)
            document.insert(reading.pieces)
            if reading.failures > 0 { problem = Self.failureMessage(reading.failures) }
        }
    }

    private func insertPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var failures = 0
            for item in items {
                let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? ""
                if let data = try? await item.loadTransferable(type: Data.self) {
                    document.insertImages([NoteImagePaste.source(data: data, fileExtension: fileExtension)])
                } else {
                    failures += 1
                }
            }
            if failures > 0 { problem = Self.failureMessage(failures) }
        }
    }

    /// A frase do aviso, com o número de itens que ficaram de fora.
    static func failureMessage(_ count: Int) -> String {
        count == 1 ? "1 item não pôde ser lido." : "\(count) itens não puderam ser lidos."
    }
}
