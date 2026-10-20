import Foundation
import MuralKit

/// O que está em destaque no mural agora: a pasta em foco (sob o ponteiro), o cartão
/// sendo arrastado, a pasta que o receberia se fosse solto e o filtro da barra.
///
/// Fica fora da view para as regras de esmaecer e empilhar poderem ser testadas.
struct BoardFocus: Equatable {
    var hoveredFolder: UUID?
    var dragged: UUID?
    var dropTarget: UUID?
    var filter: BoardFilter?

    /// Destaque do cartão (1 = normal): o arrastado e a pasta de destino nunca esmaecem; com
    /// uma pasta em foco, o resto do mural esmaece; senão, vale o filtro.
    func emphasis(for item: BoardItem) -> Double {
        if item.id == dragged || item.id == dropTarget { return 1 }
        if let hoveredFolder, hoveredFolder != item.id { return 0.3 }
        return filter?.emphasis(for: item.kind) ?? 1
    }

    /// Empilhamento: o arrastado por cima de tudo, a pasta de destino logo abaixo dele, a pasta
    /// em foco acima do resto e, com um filtro, os destacados à frente dos esmaecidos. Como o
    /// esmaecido continua sólido, um cartão apagado por cima esconderia parte do destacado.
    func layer(for item: BoardItem) -> Double {
        if item.id == dragged { return 4 }
        if item.id == dropTarget { return 3 }
        if item.id == hoveredFolder { return 2 }
        return emphasis(for: item) < 1 ? 0 : 1
    }
}
