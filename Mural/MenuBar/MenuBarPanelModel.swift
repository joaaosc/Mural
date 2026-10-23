import Foundation
import MuralKit
import Observation

/// O estado do painel da barra de menus: os murais da vitrine, qual está no centro, a busca por letras e o último
/// mural aberto por ali.
///
/// Sem SwiftUI, para ser testado sem desenhar nada. Quem decide qual mural abre no centro e como a busca anda pela lista
/// é `BoardPicker`; as capas são de `BoardCoverService`; a ordem em que elas são pedidas, de `CoverflowGeometry`.
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

    /// A chave, nas preferências, do último mural a que o painel levou: o `uuidString` do `BoardID`.
    static let lastDestinationKey = "menuBarLastBoardID"
    /// A pausa, em segundos, que faz a busca por letras recomeçar: digitar com um intervalo maior que ela começa outra
    /// busca; com um intervalo menor ou igual, continua a anterior.
    static let typingPause: TimeInterval = 1

    private let library: BoardLibrary
    private let activeBoard: @MainActor () -> BoardID?
    private let preferences: UserDefaults
    private let now: () -> Date

    /// As letras da busca em andamento e o instante da última.
    @ObservationIgnored private var typedText = ""
    @ObservationIgnored private var lastKeystroke: Date?

    /// - Parameters:
    ///   - library: de onde vem a lista de murais.
    ///   - covers: quem mantém as capas prontas; compartilhado entre as aberturas do painel.
    ///   - activeBoard: o mural da aba ativa na janela, se houver; consultado ao carregar.
    ///   - preferences: onde se guarda o último destino.
    ///   - now: o relógio da busca por letras; os testes trocam por um que anda quando se manda.
    init(
        library: BoardLibrary,
        covers: BoardCoverService,
        activeBoard: @escaping @MainActor () -> BoardID?,
        preferences: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.covers = covers
        self.activeBoard = activeBoard
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
        selection = BoardPicker.initialIndex(in: entries, lastDestination: lastDestination, activeBoard: activeBoard()) ?? 0
        isLoaded = true
        covers.sweep(keeping: Set(entries.map(\.manifest.id)))
        requestCovers()
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

    // MARK: Capas

    /// Pede as capas a partir do centro: o mural do centro primeiro, depois os vizinhos, para fora.
    private func requestCovers() {
        let order = CoverflowGeometry().priorityOrder(selection: selection, count: entries.count)
        covers.request(order.map { entries[$0] })
    }
}
