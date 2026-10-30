import Foundation
import MuralKit
import Observation

/// O estado da janela "Colar no mural": os murais da galeria, qual está escolhido, os jeitos de colar o texto do editor (com o
/// sugerido marcado e os que não valem desligados) e o resultado do colar.
///
/// Sem SwiftUI, para ser testado sem desenhar nada. A lista de murais é da biblioteca; as capas, de `BoardCoverService`; a
/// entrega, de `BoardDelivery`; os jeitos de colar, de `PasteKindDetector`. Colar nunca limpa o documento: o editor continua
/// aberto com o texto.
@MainActor
@Observable
final class PasteDestinationModel {
    /// Os murais, na ordem da biblioteca.
    private(set) var entries: [BoardLibraryEntry] = []
    /// O índice do mural escolhido.
    private(set) var selection = 0
    /// A leitura da biblioteca terminou, com ou sem erro.
    private(set) var isLoaded = false
    /// Por que a biblioteca não pôde ser lida; `nil` enquanto não houve falha.
    private(set) var loadError: String?
    /// Os jeitos de colar o texto agora.
    private(set) var suggestion = PasteKindSuggestion(suggested: .text, options: [])
    /// O jeito escolhido; começa no sugerido.
    private(set) var selectedKind: PasteKind = .text
    private(set) var status: PasteStatus = .idle
    /// Um aviso do colar que deu certo (uma imagem perdida); `nil` sem aviso.
    private(set) var warning: String?
    let covers: BoardCoverService

    /// A chave, nas preferências, do último mural a que o editor colou: o `uuidString` do `BoardID`.
    static let lastDestinationKey = "textEditorLastBoardID"
    /// A pausa, em segundos, que faz a busca por letras recomeçar.
    static let typingPause: TimeInterval = 1

    private let library: BoardLibrary
    private let delivery: BoardDelivery
    private let preferences: UserDefaults
    private let document: TextEditorDocument
    private let now: () -> Date

    /// A entrega em andamento. É do modelo, e não da janela: fechar a galeria não a cancela.
    @ObservationIgnored private var pasteTask: Task<Bool, Never>?
    @ObservationIgnored private var typedText = ""
    @ObservationIgnored private var lastKeystroke: Date?

    init(
        library: BoardLibrary, covers: BoardCoverService, delivery: BoardDelivery, document: TextEditorDocument,
        preferences: UserDefaults = .standard, now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.covers = covers
        self.delivery = delivery
        self.document = document
        self.preferences = preferences
        self.now = now
    }

    /// O mural escolhido, ou `nil` com a lista vazia.
    var selectedEntry: BoardLibraryEntry? {
        entries.indices.contains(selection) ? entries[selection] : nil
    }

    /// O último mural a que o editor colou.
    var lastDestination: BoardID? {
        preferences.string(forKey: Self.lastDestinationKey)
            .flatMap { UUID(uuidString: $0) }
            .map { BoardID(rawValue: $0) }
    }

    /// Há um mural, o jeito escolhido vale e nenhum colar está em andamento ou feito (um Return a mais não cola duas vezes).
    var canPaste: Bool {
        guard selectedEntry != nil, suggestion.unavailable[selectedKind] == nil, suggestion.options.contains(selectedKind) else {
            return false
        }
        switch status {
        case .idle, .failed: return true
        case .pasting, .pasted: return false
        }
    }

    /// Os jeitos que se pode escolher: os oferecidos que valem.
    var selectableKinds: [PasteKind] {
        suggestion.options.filter { suggestion.unavailable[$0] == nil }
    }

    // MARK: Carregar

    /// Lê os murais, escolhe o último destino (ou o mais recente) e recalcula os jeitos de colar a partir do texto de agora. Chamado
    /// a cada abertura da janela: zera o resultado do colar anterior.
    func load() async {
        status = .idle
        warning = nil
        refreshKinds(resettingSelection: true)
        let listing: BoardLibraryListing
        do {
            listing = try await library.listReport()
        } catch {
            entries = []
            selection = 0
            loadError = error.localizedDescription
            isLoaded = true
            return
        }
        entries = listing.entries
        loadError = nil
        selection = BoardPicker.initialIndex(in: entries, lastDestination: lastDestination, activeBoard: nil) ?? 0
        isLoaded = true
        requestCovers()
    }

    /// Recalcula os jeitos de colar a partir do texto de agora (o editor pode ter mudado com a galeria aberta). Mantém o jeito
    /// escolhido se ele ainda vale; senão, vai para o sugerido. Com `resettingSelection` (ao abrir a janela), começa sempre no
    /// sugerido.
    func refreshKinds(resettingSelection: Bool = false) {
        suggestion = PasteKindDetector.detect(text: document.text, hasEmbeds: document.hasEmbeds, hasImages: document.hasImages)
        if resettingSelection || !selectableKinds.contains(selectedKind) {
            selectedKind = suggestion.options.contains(suggestion.suggested) ? suggestion.suggested : (suggestion.options.first ?? .text)
        }
    }

    // MARK: Murais

    /// Escolhe o mural do índice, preso à lista.
    func select(_ index: Int) {
        guard !entries.isEmpty else { return }
        let target = min(max(index, 0), entries.count - 1)
        guard target != selection else { return }
        selection = target
        requestCovers()
    }

    /// Anda `offset` murais, parando nas pontas.
    func move(by offset: Int) {
        select(selection + offset)
    }

    /// Vai ao primeiro mural.
    func selectFirst() {
        select(0)
    }

    /// Vai ao último mural.
    func selectLast() {
        select(entries.count - 1)
    }

    /// Letras digitadas: leva ao mural cujo nome começa com o que se digitou (a busca recomeça depois de uma pausa).
    func type(_ characters: String) {
        let moment = now()
        if let last = lastKeystroke, moment.timeIntervalSince(last) > Self.typingPause { typedText = "" }
        lastKeystroke = moment
        typedText += characters
        guard let match = BoardPicker.index(matching: typedText, in: entries, startingAt: selection) else { return }
        select(match)
    }

    // MARK: Jeitos de colar

    /// Escolhe o jeito, se ele vale.
    func selectKind(_ kind: PasteKind) {
        guard selectableKinds.contains(kind) else { return }
        selectedKind = kind
    }

    /// Anda `offset` jeitos que valem, parando nas pontas.
    func moveKind(by offset: Int) {
        let kinds = selectableKinds
        guard let index = kinds.firstIndex(of: selectedKind) else {
            if let first = kinds.first { selectedKind = first }
            return
        }
        selectedKind = kinds[min(max(index + offset, 0), kinds.count - 1)]
    }

    // MARK: Colar

    /// O conteúdo a entregar e o tipo de cartão do texto, para o jeito dado.
    ///
    /// - Links: um cartão de link por endereço do texto.
    /// - Post-it e lista: o texto no tipo escolhido.
    /// - Nota sem cartões nem imagens: o texto como nota. Com eles, a nota inteira (`PastedNote`), que leva os anexos.
    static func content(
        for kind: PasteKind, text: String, embeds: [UUID: EmbeddedCard], images: [UUID: NoteImagePaste.Source]
    ) -> (content: ClipboardContent, textKind: ItemKind?) {
        switch kind {
        case .links:
            return (.pasted(.links(WebLink.urls(inText: text).map { LinkDraft(url: $0) })), nil)
        case .sticky, .checklist:
            return (.pasted(.text(text)), kind.itemKind)
        case .text:
            let hasParts = !NoteImageMarkup.references(in: text).cardIDs.isEmpty || !images.isEmpty
            if hasParts { return (.note(PastedNote(text: text, embeds: embeds, images: images)), nil) }
            return (.pasted(.text(text)), .text)
        }
    }

    /// Pede o colar: a entrega roda numa tarefa do modelo, que continua mesmo se a galeria fechar. Não faz nada se já há um colar
    /// em andamento ou feito.
    func requestPaste() {
        guard canPaste else { return }
        status = .pasting
        warning = nil
        pasteTask = Task { await performPaste() }
    }

    /// Entrega o texto do editor no mural escolhido, do jeito escolhido, e lembra o mural. O documento não é limpo.
    /// - Returns: `true` se o cartão entrou no mural.
    func paste() async -> Bool {
        guard canPaste else { return false }
        status = .pasting
        warning = nil
        return await performPaste()
    }

    private func performPaste() async -> Bool {
        guard let entry = selectedEntry else {
            status = .failed("Não há um mural para receber o texto.")
            return false
        }
        // O editor pode ter ganhado cartões ou imagens depois de a galeria abrir: os jeitos valem para o texto de agora.
        refreshKinds()
        let built = Self.content(for: selectedKind, text: document.text, embeds: document.embeds, images: document.images)
        switch await delivery.deliver(built.content, textKind: built.textKind, to: entry) {
        case .delivered:
            preferences.set(entry.manifest.id.rawValue.uuidString, forKey: Self.lastDestinationKey)
            covers.request([entry])
            warning = delivery.lastWarning
            status = .pasted("Colado em \(entry.manifest.name)")
            return true
        case .failed(let message):
            status = .failed(message)
            return false
        }
    }

    // MARK: Capas

    /// Pede as capas a partir do mural escolhido, para fora: ele, o seguinte, o anterior, e assim por diante.
    private func requestCovers() {
        var order = [selection]
        var distance = 1
        while order.count < entries.count {
            if entries.indices.contains(selection + distance) { order.append(selection + distance) }
            if entries.indices.contains(selection - distance) { order.append(selection - distance) }
            distance += 1
        }
        covers.request(order.map { entries[$0] })
    }
}
