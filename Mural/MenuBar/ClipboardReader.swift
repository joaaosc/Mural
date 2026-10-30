import AppKit
import MuralKit

/// O que o painel da barra de menus sabe da área de transferência.
enum ClipboardState: Equatable, Sendable {
    /// Vazia, ou sem nada que o mural cole.
    case nothing
    /// Marcada pelo app de origem como privada ou temporária (uma senha, por exemplo): nunca é lida.
    case protected
    /// O macOS nega a leitura automática do conteúdo; o ⌘V da pessoa ainda cola.
    case deniedBySystem
    /// Há o que colar. Com `ClipboardReading.content` o conteúdo foi lido e o tipo traz contagem e texto; sem ele o tipo é só o
    /// palpite pelos identificadores (`ClipboardKind.isRead` é falso enquanto faltam a contagem ou o texto; imagem e PDF
    /// não precisam de leitura para isso e podem vir sem `content`).
    case available(ClipboardKind)
}

/// O estado da área de transferência e, quando já foi lido, o que há para colar.
struct ClipboardReading {
    let state: ClipboardState
    /// `nil` enquanto o conteúdo não foi lido, e sempre que `state` não é `.available`.
    let content: ClipboardContent?
}

/// Lê a área de transferência para o painel, em dois momentos: ao abrir (`peek()`) e ao colar (`read()`).
///
/// Desde o macOS 15.4, ler o conteúdo da área de transferência geral sem um pedido de colar da pessoa faz o sistema
/// perguntar "Permitir colar?" (`NSPasteboard.accessBehavior` em `.default` ou `.ask`) ou negar (`.alwaysDeny`); com
/// `.alwaysAllow` lê sem perguntar. O colar pedido pela pessoa (⌘V) é sempre permitido. Por isso `peek()` olha só os
/// tipos, que não geram aviso, e quem lê os dados é `read()`, chamado de dentro do próprio colar. Conteúdo marcado como
/// privado ou temporário nunca é lido, por nenhum dos dois.
@MainActor
final class ClipboardReader {
    /// Como se descobre o comportamento de acesso da área de transferência. Os testes trocam: uma área de transferência
    /// nomeada nunca passou pelo aviso do sistema e não tem um `accessBehavior` que valha.
    typealias AccessBehaviorProvider = @MainActor (NSPasteboard) -> NSPasteboard.AccessBehavior

    /// Marcas que apps de senhas e de uso único põem para pedir que o conteúdo não seja guardado nem lido (a convenção do
    /// nspasteboard.org).
    private static let protectedMarkers: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    private let pasteboard: NSPasteboard
    private let currentAccessBehavior: AccessBehaviorProvider

    /// - Parameters:
    ///   - pasteboard: a área de transferência lida; a geral por padrão. Os testes usam uma nomeada.
    ///   - accessBehavior: o comportamento de acesso dela; por padrão o que o sistema informa.
    init(
        pasteboard: NSPasteboard = .general,
        accessBehavior: @escaping AccessBehaviorProvider = { $0.accessBehavior }
    ) {
        self.pasteboard = pasteboard
        self.currentAccessBehavior = accessBehavior
    }

    // MARK: Leitura

    /// O que a área de transferência guarda, para o painel que acabou de abrir. Olha só os tipos; os dados só são lidos com
    /// `.alwaysAllow`, que não gera aviso.
    ///
    /// Em ordem: marca de privado ou temporário (`.protected`); leitura automática negada (`.deniedBySystem`); nenhum tipo
    /// que o mural cole (`.nothing`); `.alwaysAllow` (devolve `read()`); senão o palpite pelos tipos, sem conteúdo.
    func peek() -> ClipboardReading {
        let types = Self.typeIdentifiers(of: pasteboard)
        if Self.hasProtectedMarker(types) { return Self.reading(.protected) }
        let behavior = currentAccessBehavior(pasteboard)
        if behavior == .alwaysDeny { return Self.reading(.deniedBySystem) }
        let guess = ClipboardKind.hint(typeIdentifiers: types)
        if guess == .nothing { return Self.reading(.nothing) }
        if behavior == .alwaysAllow { return read() }
        return ClipboardReading(state: .available(guess), content: nil)
    }

    /// Lê o conteúdo para colar. Deve ser chamado de forma síncrona de dentro do colar pedido pela pessoa (⌘V), que o sistema
    /// sempre permite; fora dele a leitura segue o `accessBehavior` e pode gerar o aviso ou ser negada.
    ///
    /// Música vem primeiro, como no ⌘V (`MusicPasteboardReader`), depois os contatos de um vCard (`ContactVCardReader`); o resto, de `PasteboardImporter.read`. Sem nada que
    /// colar, o resultado é `.deniedBySystem` se o comportamento for `.alwaysDeny` (a leitura negada volta vazia e isso
    /// não se distingue de uma área de transferência vazia), e `.nothing` nos outros casos.
    func read() -> ClipboardReading {
        if Self.hasProtectedMarker(Self.typeIdentifiers(of: pasteboard)) { return Self.reading(.protected) }
        let drafts = MusicPasteboardReader.drafts(from: pasteboard)
        let contacts = drafts.isEmpty ? ContactVCardReader.drafts(from: pasteboard) : []
        let content: ClipboardContent =
            if !drafts.isEmpty { .music(drafts) } else if !contacts.isEmpty { .contacts(contacts) } else {
                .pasted(PasteboardImporter.read(from: pasteboard))
            }
        let kind = Self.kind(of: content)
        guard kind != .nothing else {
            return Self.reading(currentAccessBehavior(pasteboard) == .alwaysDeny ? .deniedBySystem : .nothing)
        }
        return ClipboardReading(state: .available(kind), content: content)
    }

    // MARK: Tipos

    /// O tipo do conteúdo já lido, com contagem e texto. Um dado que não é imagem nem PDF (um vídeo, por exemplo) vale como
    /// um arquivo.
    nonisolated static func kind(of content: ClipboardContent) -> ClipboardKind {
        switch content {
        case .contacts(let drafts):
            .contact(count: drafts.count)
        case .note(let note):
            .text(note.text)
        case .music(let drafts):
            .music(count: drafts.count)
        case .pasted(.files(let urls)):
            .files(count: urls.count)
        case .pasted(.data(_, _, .image, _)), .pasted(.imageNeedingConversion):
            .image
        case .pasted(.data(_, _, .pdf, _)):
            .pdf
        case .pasted(.data):
            .files(count: 1)
        case .pasted(.links(let links)):
            .links(count: links.count)
        case .pasted(.text(let text)):
            .text(text)
        case .pasted(.nothing):
            .nothing
        }
    }

    /// Os identificadores de tipo da área de transferência, sem ler dados: os dela e os de cada item, sem repetir, na ordem
    /// da primeira ocorrência. Com vários itens, os tipos de um item podem faltar na lista da própria área de transferência.
    static func typeIdentifiers(of pasteboard: NSPasteboard) -> [String] {
        let lists = [pasteboard.types ?? []] + (pasteboard.pasteboardItems ?? []).map(\.types)
        var seen = Set<String>()
        var identifiers: [String] = []
        for type in lists.joined() where seen.insert(type.rawValue).inserted {
            identifiers.append(type.rawValue)
        }
        return identifiers
    }

    private static func hasProtectedMarker(_ typeIdentifiers: [String]) -> Bool {
        !protectedMarkers.isDisjoint(with: typeIdentifiers)
    }

    private static func reading(_ state: ClipboardState) -> ClipboardReading {
        ClipboardReading(state: state, content: nil)
    }
}
