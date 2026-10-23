import Foundation

/// Regras da vitrine de murais do painel da barra de menus: qual mural fica no centro ao abrir e como a busca
/// por nome anda pela lista. As duas funções respeitam a ordem da lista recebida, sem reordená-la.
public enum BoardPicker {
    /// O mural que fica no centro da vitrine ao abrir: o último usado pelo painel; senão o da aba ativa; senão o
    /// de `manifest.updatedAt` mais recente (em empate, o primeiro da lista). Um id que não está na lista é ignorado.
    /// - Returns: a posição na lista, ou `nil` se a lista estiver vazia.
    public static func initialIndex(in entries: [BoardLibraryEntry], lastDestination: BoardID?, activeBoard: BoardID?) -> Int? {
        guard !entries.isEmpty else { return nil }
        for id in [lastDestination, activeBoard] {
            if let id, let index = entries.firstIndex(where: { $0.manifest.id == id }) { return index }
        }
        var newest = 0
        for index in entries.indices.dropFirst() where entries[index].manifest.updatedAt > entries[newest].manifest.updatedAt {
            newest = index
        }
        return newest
    }

    /// Procura um mural pelo nome, a partir de `start` (inclusive) e dando a volta na lista: primeiro o nome que
    /// começa com o texto; se nenhum começa, o primeiro que o contém. Não diferencia maiúsculas nem acentos
    /// ("cafe" acha "Café"), e os espaços e quebras de linha nas pontas do texto são ignorados.
    /// - Parameter start: posição por onde começar; fora da lista, também dá a volta (o tamanho da lista vira 0).
    /// - Returns: a posição na lista, ou `nil` se o texto for vazio ou só espaços, a lista estiver vazia ou nenhum nome servir.
    public static func index(matching query: String, in entries: [BoardLibraryEntry], startingAt start: Int = 0) -> Int? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !entries.isEmpty else { return nil }

        let first = ((start % entries.count) + entries.count) % entries.count
        let order = (0..<entries.count).map { (first + $0) % entries.count }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return order.first { entries[$0].manifest.name.range(of: text, options: options.union(.anchored)) != nil }
            ?? order.first { entries[$0].manifest.name.range(of: text, options: options) != nil }
    }
}
