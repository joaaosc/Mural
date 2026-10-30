import Foundation
import MuralKit
import Observation

/// Em que pé está o colar do painel: nada em andamento, entregando, trabalhando no editor (abrindo-o ou lendo a edição),
/// entregue (com a frase que o painel mostra) ou falho (com o motivo).
enum PasteStatus: Equatable, Sendable {
    case idle
    case pasting
    /// Abrindo o app de edição ou lendo a edição de volta; traz a frase que o painel mostra.
    case working(String)
    case pasted(String)
    case failed(String)

    /// Está abrindo o editor ou lendo a edição.
    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

/// De onde vem o que o painel oferece para colar.
enum PasteSource: Equatable, Sendable {
    /// O que está na área de transferência.
    case clipboard
    /// Uma edição pendente: o conteúdo foi aberto num app de edição e espera ser colado.
    case edit
}

/// O estado do painel da barra de menus: os murais da vitrine, qual está no centro, a busca por letras, o último
/// mural aberto por ali, o que há para colar nele, em que etapa está o teclado (``PanelStage``) e como formatar o texto
/// copiado.
///
/// Sem SwiftUI, para ser testado sem desenhar nada. Quem decide qual mural abre no centro e como a busca anda pela lista
/// é `BoardPicker`; as capas são de `BoardCoverService`; a ordem em que elas são pedidas, de `CoverflowGeometry`; a
/// leitura da área de transferência, de `ClipboardReader`; a entrega do que foi copiado, de `BoardDelivery`; as
/// formatações do texto, de `PasteTextFormat`.
@MainActor
@Observable
final class MenuBarPanelModel {
    /// Os murais, na ordem da biblioteca.
    private(set) var entries: [BoardLibraryEntry] = []
    /// O índice do mural do centro da vitrine.
    private(set) var selection = 0
    /// A leitura da biblioteca terminou, com ou sem erro.
    private(set) var isLoaded = false
    /// Por que a biblioteca não pôde ser lida; `nil` enquanto não houve falha.
    private(set) var loadError: String?
    let covers: BoardCoverService

    /// O que o painel sabe da área de transferência: o palpite de quando abriu ou, depois do colar, o que foi lido.
    private(set) var clipboard: ClipboardState = .nothing
    /// O que foi lido da área de transferência; `nil` enquanto só se sabe o palpite pelos tipos.
    private(set) var clipboardContent: ClipboardContent?
    /// As maneiras de colar o que está copiado, na ordem em que o painel as mostra.
    private(set) var options: [PasteOption] = []
    /// O índice da opção escolhida em ``options``. Começa na sugerida, que é a do ⌘V; a vitrine não a mostra como
    /// escolhida, porque ali o teclado escolhe o mural.
    private(set) var selectedOption = 0
    private(set) var pasteStatus: PasteStatus = .idle
    /// De onde vem o conteúdo: a área de transferência ou uma edição pendente.
    private(set) var source: PasteSource = .clipboard
    /// O nome do app que edita o conteúdo atual (guardado ao montar as opções, para as vistas não consultarem o sistema);
    /// `nil` quando não há como editá-lo e, por isso, não há a opção de editar.
    private(set) var editorName: String?

    /// A etapa em que está o teclado. O painel abre na vitrine.
    private(set) var stage: PanelStage = .boards
    /// As formatações que o texto copiado aceita, na ordem do painel; vazio quando o que está copiado não é texto.
    private(set) var formats: [PasteTextFormat] = []
    /// A formatação escolhida; começa no texto como foi copiado.
    private(set) var selectedFormat: PasteTextFormat = .original

    /// A chave, nas preferências, do último mural a que o painel levou: o `uuidString` do `BoardID`.
    static let lastDestinationKey = "menuBarLastBoardID"
    /// A pausa, em segundos, que faz a busca por letras recomeçar: digitar com um intervalo maior que ela começa outra
    /// busca; com um intervalo menor ou igual, continua a anterior.
    static let typingPause: TimeInterval = 1

    private static let nothingToPasteMessage = "Não há nada para colar."
    private static let protectedMessage = "O que está copiado é privado (como uma senha) e o Mural não lê."
    private static let deniedMessage = "O macOS não deixou o Mural ler o que foi copiado."
    private static let noBoardMessage = "Não há um mural para receber o que foi copiado."

    private let library: BoardLibrary
    private let activeBoard: @MainActor () -> BoardID?
    private let reader: ClipboardReader
    private let delivery: BoardDelivery
    private let editor: PasteEditor?
    private let preferences: UserDefaults
    private let now: () -> Date

    /// As letras da busca em andamento e o instante da última.
    @ObservationIgnored private var typedText = ""
    @ObservationIgnored private var lastKeystroke: Date?
    /// A pessoa mudou de etapa com o teclado: o painel que abre numa edição pendente não a tira de onde ela está.
    @ObservationIgnored private var stageChangedByPerson = false

    /// - Parameters:
    ///   - library: de onde vem a lista de murais.
    ///   - covers: quem mantém as capas prontas; compartilhado entre as aberturas do painel.
    ///   - activeBoard: o mural da aba ativa na janela, se houver; consultado ao carregar.
    ///   - reader: quem olha e lê a área de transferência. Sem valor padrão: o padrão leria a área de transferência geral.
    ///   - delivery: quem entrega o que foi copiado no mural do centro.
    ///   - editor: a edição antes de colar, que vive além do painel; sem ele, não há a opção de editar.
    ///   - preferences: onde se guarda o último destino.
    ///   - now: o relógio da busca por letras; os testes trocam por um que anda quando se manda.
    init(
        library: BoardLibrary,
        covers: BoardCoverService,
        activeBoard: @escaping @MainActor () -> BoardID?,
        reader: ClipboardReader,
        delivery: BoardDelivery,
        editor: PasteEditor? = nil,
        preferences: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.covers = covers
        self.activeBoard = activeBoard
        self.reader = reader
        self.delivery = delivery
        self.editor = editor
        self.preferences = preferences
        self.now = now
    }

    /// O mural do centro da vitrine, ou `nil` com a lista vazia.
    var selectedEntry: BoardLibraryEntry? {
        entries.indices.contains(selection) ? entries[selection] : nil
    }

    /// O último mural a que o painel levou; `nil` se nunca levou ou se o valor guardado não é um identificador.
    var lastDestination: BoardID? {
        preferences.string(forKey: Self.lastDestinationKey)
            .flatMap { UUID(uuidString: $0) }
            .map { BoardID(rawValue: $0) }
    }

    // MARK: Carregar

    /// Lê a lista de murais, escolhe o do centro (o último destino; senão o da aba ativa; senão o editado mais
    /// recentemente) e pede as capas a partir dele.
    ///
    /// Só uma leitura que deu certo apaga as capas de murais que não existem mais: se a leitura falhou, não se sabe quais
    /// murais existem, e apagar por causa de um erro de leitura levaria capas de murais que estão lá.
    ///
    /// Com uma edição pendente, o mural do centro é o dela e a área de transferência não é olhada: o painel mostra o que
    /// foi editado, lido de volta (``loadEdit(_:)``). Sem edição, termina olhando a área de transferência
    /// (``prepareClipboard()``). Se a lista não pôde ser lida não há para onde colar, e nada disso é feito. Um erro de
    /// edição que chegou com o painel fechado aparece uma vez.
    func load() async {
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
        selection =
            BoardPicker.initialIndex(
                in: entries, lastDestination: editor?.pending?.boardID ?? lastDestination, activeBoard: activeBoard()) ?? 0
        isLoaded = true
        covers.sweep(keeping: Set(entries.map(\.manifest.id)))
        requestCovers()
        if let pending = editor?.pending {
            await loadEdit(pending)
            if !stageChangedByPerson, stages.contains(.paste) { stage = .paste }
        } else {
            prepareClipboard()
        }
        if case .idle = pasteStatus, let message = editor?.takeLastFailure() {
            pasteStatus = .failed(message)
        }
    }

    /// Monta o painel sobre a edição pendente: só o tipo é conhecido até a leitura terminar, e então as opções são as do
    /// conteúdo editado (colar, voltar ao editor, descartar). Se a leitura falha, ficam só as duas últimas.
    private func loadEdit(_ pending: PasteEditor.Pending) async {
        guard let editor else { return }
        source = .edit
        editorName = pending.editor.name
        let hint: ClipboardKind =
            switch pending.session.kind {
            case .text: .text(nil)
            case .image: .image
            case .pdf: .pdf
            }
        clipboard = .available(hint)
        clipboardContent = nil
        options = []
        selectedOption = 0
        formats = []
        pasteStatus = .working("Lendo a edição…")
        do {
            let content = try await editor.read()
            apply(
                ClipboardReading(state: .available(ClipboardReader.kind(of: .pasted(content))), content: .pasted(content)))
            pasteStatus = .idle
        } catch {
            apply(ClipboardReading(state: .nothing, content: nil))
            pasteStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: Seleção

    /// Põe o mural do índice no centro, preso à lista: um índice fora dela vai para a ponta mais próxima. Sem murais, não
    /// faz nada.
    func select(_ index: Int) {
        guard !entries.isEmpty else { return }
        let target = min(max(index, 0), entries.count - 1)
        guard target != selection else { return }
        selection = target
        requestCovers()
    }

    /// Anda `offset` murais a partir do centro, parando nas pontas (sem dar a volta).
    func move(by offset: Int) {
        select(selection + offset)
    }

    /// Uma ou mais letras digitadas na vitrine: leva ao mural cujo nome começa com o que se digitou.
    ///
    /// As letras seguidas sem uma pausa maior que ``typingPause`` formam uma busca só ("v" e depois "i" procuram "vi");
    /// depois da pausa, a busca recomeça. A procura parte do mural do centro, então continuar digitando não pula para
    /// outro enquanto o nome do centro ainda serve.
    func type(_ characters: String) {
        let moment = now()
        if let last = lastKeystroke, moment.timeIntervalSince(last) > Self.typingPause {
            typedText = ""
        }
        lastKeystroke = moment
        typedText += characters
        guard let match = BoardPicker.index(matching: typedText, in: entries, startingAt: selection) else { return }
        select(match)
    }

    // MARK: Etapas

    /// As etapas que o painel tem agora, na ordem do Tab: a vitrine sempre; as maneiras de colar quando há um mural no
    /// centro e alguma opção de colar; a formatação quando, além disso, o que está copiado é texto e a opção escolhida o
    /// cola (escolher "Editar" ou "Descartar" tira a etapa).
    var stages: [PanelStage] {
        guard selectedEntry != nil, !options.isEmpty else { return [.boards] }
        return formats.isEmpty || !selectedOptionPastesText ? [.boards, .paste] : [.boards, .paste, .format]
    }

    /// A opção escolhida cola texto: é uma das de tipo de cartão ou a que lê na hora.
    private var selectedOptionPastesText: Bool {
        options.indices.contains(selectedOption) && Self.pastesText(options[selectedOption])
    }

    private static func pastesText(_ option: PasteOption) -> Bool {
        switch option.action {
        case .text, .read: true
        case .asRead, .edit, .discardEdit: false
        }
    }

    /// Tab: vai para a etapa seguinte e, depois da última, volta à vitrine.
    /// - Returns: `false`, sem mudar nada, quando a vitrine é a única etapa.
    @discardableResult
    func advanceStage() -> Bool {
        let available = stages
        guard available.count > 1 else { return false }
        let index = available.firstIndex(of: stage) ?? 0
        stage = available[(index + 1) % available.count]
        stageChangedByPerson = true
        return true
    }

    /// ⇧Tab: volta uma etapa, parando na vitrine.
    /// - Returns: `false`, sem mudar nada, já na vitrine.
    @discardableResult
    func retreatStage() -> Bool {
        let available = stages
        guard let index = available.firstIndex(of: stage), index > 0 else { return false }
        stage = available[index - 1]
        stageChangedByPerson = true
        return true
    }

    /// Esc fora da vitrine: volta direto a ela.
    /// - Returns: `false` já na vitrine, onde o Esc fecha o painel.
    @discardableResult
    func returnToBoards() -> Bool {
        guard stage != .boards else { return false }
        stage = .boards
        stageChangedByPerson = true
        return true
    }

    /// Uma etapa que deixou de existir (as opções mudaram depois de ler a área de transferência) dá lugar à anterior que
    /// ainda existe.
    private func keepStageAvailable() {
        let available = stages
        guard !available.contains(stage) else { return }
        stage = stage == .format && available.contains(.paste) ? .paste : .boards
    }

    // MARK: Formatação

    /// Anda `offset` formatações a partir da escolhida, parando nas pontas (sem dar a volta).
    func moveFormat(by offset: Int) {
        guard let index = formats.firstIndex(of: selectedFormat) else { return }
        selectFormat(formats[min(max(index + offset, 0), formats.count - 1)])
    }

    /// Escolhe a formatação, se o texto copiado a aceita; senão não faz nada.
    func selectFormat(_ format: PasteTextFormat) {
        guard formats.contains(format) else { return }
        selectedFormat = format
    }

    /// O texto copiado com a formatação, para a prévia; `nil` enquanto o texto não foi lido (o macOS só deixa ler num
    /// colar pedido pela pessoa) e quando o que está copiado não é texto.
    func formattedText(_ format: PasteTextFormat) -> String? {
        guard case .pasted(.text(let text))? = clipboardContent else { return nil }
        return Self.formatted(text, with: format)
    }

    /// O texto com a formatação; uma formatação que o deixaria vazio (só havia caracteres invisíveis) não vale, e o texto
    /// fica como veio.
    private static func formatted(_ text: String, with format: PasteTextFormat) -> String {
        let result = format.apply(to: text)
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : result
    }

    // MARK: Abrir

    /// Guarda o mural como o último destino do painel: é o que fica no centro da próxima vez que o painel abrir.
    func rememberDestination(_ id: BoardID) {
        preferences.set(id.rawValue.uuidString, forKey: Self.lastDestinationKey)
    }

    /// Abre o mural do índice no app: lembra o destino, abre (ou volta para) a aba dele, traz a janela para a frente e
    /// devolve o teclado ao mural. Um índice fora da lista não faz nada.
    func open(_ index: Int, in tabs: MuralTabs) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        rememberDestination(entry.manifest.id)
        tabs.open(entry.route, title: entry.manifest.name)
        tabs.showWindow()
        tabs.focusBoard()
    }

    // MARK: Colar

    /// O tipo do que está copiado; `.nothing` quando não há o que colar.
    var clipboardKind: ClipboardKind {
        if case .available(let kind) = clipboard { return kind }
        return .nothing
    }

    /// Dá para colar agora: há um mural no centro e, ou há opções de colar, ou o macOS nega a leitura automática (o ⌘V
    /// da pessoa ainda pode ler).
    var canPaste: Bool {
        selectedEntry != nil && (!options.isEmpty || clipboard == .deniedBySystem)
    }

    /// Olha a área de transferência e monta as opções de colar, com a sugerida escolhida. Só os tipos são olhados, a menos
    /// que o sistema deixe ler sem avisar (`ClipboardReader.peek()`).
    func prepareClipboard() {
        apply(reader.peek())
    }

    /// Anda `offset` opções a partir da escolhida, parando nas pontas (sem dar a volta).
    func moveOption(by offset: Int) {
        selectOption(selectedOption + offset)
    }

    /// Escolhe a opção do índice, preso à lista: um índice fora dela vai para a ponta mais próxima. Sem opções, não faz nada.
    func selectOption(_ index: Int) {
        guard !options.isEmpty else { return }
        selectedOption = min(max(index, 0), options.count - 1)
        keepStageAvailable()
    }

    /// O ⌘V nunca descarta: com "Descartar a edição" escolhida, volta à opção sugerida.
    func preferPasteOverDiscard() {
        guard options.indices.contains(selectedOption), options[selectedOption].action == .discardEdit else { return }
        selectedOption = PasteOptions.suggestedIndex(in: options) ?? 0
        keepStageAvailable()
    }

    /// A parte do colar que precisa acontecer de forma síncrona, dentro do tratamento da tecla ou do clique: ler a área
    /// de transferência. O macOS sempre deixa ler num colar pedido pela pessoa; fora dele pode perguntar "Permitir colar?".
    /// Quem chama deve chamar esta função antes de qualquer `await`, e só então ``paste()``.
    ///
    /// Se o conteúdo ainda não foi lido, lê agora. Sem nada para colar, o motivo fica em ``pasteStatus``.
    /// - Returns: `true` se pode seguir para ``paste()``. É `false` quando não há o que colar, quando já há uma entrega
    ///   em andamento ou feita (um Return a mais não cola duas vezes) e quando acabou de ler um texto com mais de um tipo
    ///   de cartão possível: o painel passa às maneiras de colar, e a pessoa escolhe o tipo e confirma com um segundo
    ///   Return.
    ///
    /// Com uma edição pendente (``source`` em `.edit`) a área de transferência não é lida: editar e descartar não precisam
    /// de conteúdo, e colar precisa de que a edição já tenha sido lida. Se a opção escolhida era "Editar" e a leitura a faz
    /// sumir (um texto que virou links, por exemplo), nada é colado nem aberto: o painel só passa às maneiras de colar.
    func readForPaste() -> Bool {
        guard !isBusy else { return false }
        pasteStatus = .idle
        guard selectedEntry != nil else {
            pasteStatus = .failed(Self.noBoardMessage)
            return false
        }
        if source == .edit {
            guard let action = selectedAction else { return false }
            switch action {
            case .edit, .discardEdit: return true
            case .asRead, .read, .text: return clipboardContent != nil
            }
        }
        guard clipboardContent == nil else { return true }

        let chosenID = options.indices.contains(selectedOption) ? options[selectedOption].id : nil
        apply(reader.read())
        guard let content = clipboardContent else {
            pasteStatus = .failed(Self.message(for: clipboard))
            return false
        }
        if let chosenID {
            guard let index = options.firstIndex(where: { $0.id == chosenID }) else {
                if chosenID == "edit" {
                    stage = .paste
                    return false
                }
                return continuesAfterReading(content)
            }
            selectedOption = index
            keepStageAvailable()
            if options[index].action == .edit { return true }
        }
        return continuesAfterReading(content)
    }

    /// Texto com mais de um tipo de cartão possível: o painel passa às maneiras de colar para a pessoa escolher.
    private func continuesAfterReading(_ content: ClipboardContent) -> Bool {
        if case .pasted(.text) = content, options.filter({ if case .text = $0.action { true } else { false } }).count > 1 {
            stage = .paste
            return false
        }
        return true
    }

    /// Entrega o que foi lido no mural do centro, no tipo de cartão da opção escolhida e, se for texto, com a formatação
    /// escolhida, e lembra o mural como o último destino. Chamada depois de ``readForPaste()``; o resultado fica em
    /// ``pasteStatus``.
    ///
    /// Quem decide o que fazer é a ação da opção escolhida: "Editar" abre o conteúdo no app de edição (ou, com uma edição
    /// pendente, volta a ela); "Descartar a edição" a descarta e deixa o painel aberto; as demais entregam, e depois de
    /// entregar uma edição a encerram.
    /// - Returns: `true` se o cartão entrou no mural ou se o editor abriu (o painel pode fechar).
    func paste() async -> Bool {
        guard !isBusy else { return false }
        guard let entry = selectedEntry else {
            pasteStatus = .failed(Self.noBoardMessage)
            return false
        }
        guard options.indices.contains(selectedOption) else {
            pasteStatus = .failed(Self.message(for: clipboard))
            return false
        }
        switch options[selectedOption].action {
        case .edit:
            return source == .edit ? await reopenEdit() : await startEditing(in: entry)
        case .discardEdit:
            await discardEdit()
            return false
        case .asRead, .read, .text:
            break
        }
        guard var content = clipboardContent else {
            pasteStatus = .failed(Self.message(for: clipboard))
            return false
        }
        let textKind: ItemKind?
        if case .text(let kind) = options[selectedOption].action {
            textKind = kind
        } else {
            textKind = nil
        }
        if case .pasted(.text(let text)) = content {
            content = .pasted(.text(Self.formatted(text, with: selectedFormat)))
        }

        pasteStatus = .pasting
        switch await delivery.deliver(content, textKind: textKind, to: entry) {
        case .delivered:
            rememberDestination(entry.manifest.id)
            pasteStatus = .pasted("Colado em \(entry.manifest.name)")
            if source == .edit { await editor?.finish() }
            // Com o mural aberto, a capa é redesenhada do modelo vivo e mostra o cartão novo; com ele fechado, a entrega
            // já refez a capa e este pedido não desenha nada.
            covers.request([entry])
            return true
        case .failed(let message):
            pasteStatus = .failed(message)
            return false
        }
    }

    /// Abre o conteúdo lido no app de edição e passa a esperar pela edição. Não lembra o mural como destino: isso só
    /// acontece num colar de verdade.
    ///
    /// O painel fecha sozinho quando o editor toma o foco, e a tarefa de colar da vista é cancelada com ele; por isso, só
    /// uma falha vista com a tarefa viva é mostrada aqui e descartada do editor. A que chega depois do fechamento fica
    /// guardada para a próxima abertura.
    private func startEditing(in entry: BoardLibraryEntry) async -> Bool {
        guard let editor, case .pasted(let content)? = clipboardContent, let kind = PasteEditKind(clipboardKind) else {
            pasteStatus = .failed(PasteEditFiles.Failure.unsupported.errorDescription ?? Self.nothingToPasteMessage)
            return false
        }
        pasteStatus = .working("Abrindo com \(editorName ?? "o editor")…")
        switch await editor.begin(content, as: kind, board: entry) {
        case .opened(let pending):
            pasteStatus = .pasted(Self.editingMessage(pending.editor.name))
            return true
        case .failed(let message):
            pasteStatus = .failed(message)
            if !Task.isCancelled { _ = editor.takeLastFailure() }
            return false
        }
    }

    /// Abre de novo a edição pendente, para quem fechou a janela do editor sem colar.
    private func reopenEdit() async -> Bool {
        guard let editor, let pending = editor.pending else {
            pasteStatus = .failed(PasteEditFiles.Failure.missing.errorDescription ?? Self.nothingToPasteMessage)
            return false
        }
        pasteStatus = .working("Abrindo com \(pending.editor.name)…")
        if let message = await editor.reopen() {
            pasteStatus = .failed(message)
            return false
        }
        pasteStatus = .pasted(Self.editingMessage(pending.editor.name))
        return true
    }

    /// Descarta a edição pendente e volta ao que está na área de transferência.
    private func discardEdit() async {
        await editor?.discard()
        source = .clipboard
        clipboardContent = nil
        pasteStatus = .idle
        prepareClipboard()
    }

    private static func editingMessage(_ name: String) -> String {
        "Editando com \(name). Volte ao painel para colar."
    }

    /// A ação da opção escolhida; `nil` sem opções.
    private var selectedAction: PasteOption.Action? {
        options.indices.contains(selectedOption) ? options[selectedOption].action : nil
    }

    /// Há uma entrega ou um editor em andamento, ou uma entrega feita: outro pedido de colar seria um cartão repetido.
    private var isBusy: Bool {
        switch pasteStatus {
        case .pasting, .working, .pasted: true
        case .idle, .failed: false
        }
    }

    private func apply(_ reading: ClipboardReading) {
        clipboard = reading.state
        clipboardContent = reading.content
        switch source {
        case .clipboard:
            let app = PasteEditKind(clipboardKind).flatMap { editor?.editor(for: $0) }
            editorName = app?.name
            options = PasteOptions.options(for: clipboardKind, allowsEditing: app != nil)
        case .edit:
            editorName = editor?.pending?.editor.name
            options = PasteOptions.options(forEdited: clipboardKind)
        }
        selectedOption = PasteOptions.suggestedIndex(in: options) ?? 0
        // Texto ainda não lido também aceita formatação: ela vale para o que o colar ler. Sem opção que cole texto (texto
        // editado em branco), não há o que formatar.
        if case .text = clipboardKind, options.contains(where: Self.pastesText) {
            formats = PasteTextFormat.allCases
        } else {
            formats = []
        }
        if !formats.contains(selectedFormat) { selectedFormat = .original }
        keepStageAvailable()
    }

    /// Por que não há o que colar, conforme o que se sabe da área de transferência.
    private static func message(for state: ClipboardState) -> String {
        switch state {
        case .protected: protectedMessage
        case .deniedBySystem: deniedMessage
        case .nothing, .available: nothingToPasteMessage
        }
    }

    // MARK: Capas

    /// Pede as capas a partir do centro: o mural do centro primeiro, depois os vizinhos, para fora.
    private func requestCovers() {
        let order = CoverflowGeometry().priorityOrder(selection: selection, count: entries.count)
        covers.request(order.map { entries[$0] })
    }
}
