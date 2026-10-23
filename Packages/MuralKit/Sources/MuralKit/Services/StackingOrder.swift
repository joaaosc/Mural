import Foundation

/// A ordem de empilhamento dos cartões como números, para o iCloud.
///
/// O iCloud recebe os cartões um a um, sem a lista. No Mac a lista `Board.items` continua mandando: ela define quem fica por cima
/// (`Board.move` põe o cartão no fim), e o número `layer` de cada cartão reproduz essa ordem para os outros Macs. Quando a ordem
/// muda, só os cartões que saíram do lugar ganham número novo, para uma mudança custar o menor número possível de cartões enviados.
public enum StackingOrder {
    /// Os números que precisam mudar para que ordenar `order` pelo `layer` volte a reproduzi-la.
    ///
    /// Fica como está a maior sequência de cartões que já segue a ordem (pelos números anteriores, na sequência de `order`); em
    /// empate de tamanho, vale a que mantém os cartões de baixo, e assim o cartão levado ao topo é o único a mudar. Os outros ganham
    /// números entre os vizinhos mantidos, igualmente espaçados; depois do último, `último + 1`, `+ 2`…; antes do primeiro,
    /// `primeiro - 1`, `- 2`…; sem nenhum mantido, `0`, `1`, `2`…
    ///
    /// Se a precisão do `Double` não deixa números estritamente entre os vizinhos, todos são renumerados de `0` em diante, na ordem
    /// de `order`. Número anterior que não é finito conta como ausente; ids de `previous` que não estão em `order` são ignorados, e
    /// um id repetido em `order` vale só na primeira vez.
    /// - Returns: apenas os cartões cujo número muda (novos ou movidos).
    public static func assignments(for order: [UUID], previous: [UUID: Double]) -> [UUID: Double] {
        let ids = uniqueIDs(order)
        var known: [(position: Int, layer: Double)] = []
        for (position, id) in ids.enumerated() {
            if let layer = previous[id], layer.isFinite { known.append((position, layer)) }
        }
        var kept: [Int: Double] = [:]
        for index in longestIncreasingSubsequence(of: known.map(\.layer)) {
            kept[known[index].position] = known[index].layer
        }

        // O número final de cada posição: os mantidos como estão e, nos vãos entre eles, os novos.
        var layers: [Double] = []
        layers.reserveCapacity(ids.count)
        var gap = 0
        var lower: Double?
        for position in ids.indices {
            guard let layer = kept[position] else {
                gap += 1
                continue
            }
            layers.append(contentsOf: spacedLayers(count: gap, between: lower, and: layer))
            layers.append(layer)
            gap = 0
            lower = layer
        }
        layers.append(contentsOf: spacedLayers(count: gap, between: lower, and: nil))

        guard layers.allSatisfy(\.isFinite), zip(layers, layers.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, Double($0)) })
        }
        var changes: [UUID: Double] = [:]
        for (position, id) in ids.enumerated() where kept[position] == nil { changes[id] = layers[position] }
        return changes
    }

    /// Os ids na ordem crescente de `layer`, com empate pelo `uuidString`, para todos os Macs chegarem à mesma ordem. Ids sem
    /// `layer` (ou com um que não é finito) vão para o fim, na ordem em que vieram.
    public static func sorted(_ ids: [UUID], layers: [UUID: Double]) -> [UUID] {
        var placed: [(id: UUID, layer: Double)] = []
        var unplaced: [UUID] = []
        for id in ids {
            if let layer = layers[id], layer.isFinite { placed.append((id, layer)) } else { unplaced.append(id) }
        }
        placed.sort { lhs, rhs in
            lhs.layer != rhs.layer ? lhs.layer < rhs.layer : lhs.id.uuidString < rhs.id.uuidString
        }
        return placed.map(\.id) + unplaced
    }

    // MARK: Interno

    private static func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Os `count` números de um vão, crescentes. Entre dois vizinhos ficam igualmente espaçados; sem vizinho de um lado, de um em um.
    private static func spacedLayers(count: Int, between lower: Double?, and upper: Double?) -> [Double] {
        guard count > 0 else { return [] }
        switch (lower, upper) {
        case (nil, nil): return (0..<count).map { Double($0) }
        case (let lower?, nil): return (1...count).map { lower + Double($0) }
        case (nil, let upper?): return (1...count).map { upper - Double(count + 1 - $0) }
        case (let lower?, let upper?): return (1...count).map { lower + (upper - lower) * Double($0) / Double(count + 1) }
        }
    }

    /// As posições de uma maior subsequência estritamente crescente de `values`, em O(n log n). Em empate de tamanho vale a que
    /// começa mais cedo e, igualados os começos, a que segue mais cedo.
    private static func longestIncreasingSubsequence(of values: [Double]) -> [Int] {
        // Da direita para a esquerda: `lengthFrom[i]` é o tamanho da maior subsequência crescente que começa em `i`. `tails[k]` guarda
        // o menor valor (negado, para reaproveitar a busca da subsequência crescente) que, olhando da direita, fecha uma de tamanho k + 1.
        var lengthFrom = [Int](repeating: 0, count: values.count)
        var tails: [Double] = []
        for index in values.indices.reversed() {
            let key = -values[index]
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if tails[middle] < key { low = middle + 1 } else { high = middle }
            }
            if low == tails.count { tails.append(key) } else { tails[low] = key }
            lengthFrom[index] = low + 1
        }
        // Da esquerda para a direita, o primeiro cartão de cada tamanho, do maior ao 1. Basta o tamanho: o primeiro que vem depois
        // de um cartão de tamanho n e tem tamanho n - 1 sempre tem valor maior que o dele.
        var remaining = lengthFrom.max() ?? 0
        var kept: [Int] = []
        for index in values.indices where lengthFrom[index] == remaining {
            kept.append(index)
            remaining -= 1
        }
        return kept
    }
}
