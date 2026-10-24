import Foundation
import MuralKit

/// O que está em destaque no mural agora: a pasta em foco (sob o ponteiro), o cartão
/// sendo arrastado, a pasta que o receberia se fosse solto e os filtros da barra (tipo e cor).
///
/// Fica fora da view para as regras de esmaecer e empilhar poderem ser testadas.
struct BoardFocus: Equatable {
    var hoveredFolder: UUID?
    var dragged: UUID?
    var dropTarget: UUID?
    var filter: BoardFilter?
    var colorFilter: TagColor?

    /// Destaque do cartão (1 = normal): o arrastado e a pasta de destino nunca esmaecem; com
    /// uma pasta em foco, o resto do mural esmaece; senão, valem os filtros.
    func emphasis(for item: BoardItem) -> Double {
        if item.id == dragged || item.id == dropTarget { return 1 }
        if let hoveredFolder, hoveredFolder != item.id { return 0.3 }
        return BoardFilter.emphasis(for: item, kind: filter, color: colorFilter)
    }

    /// Empilhamento: o arrastado por cima de tudo, a pasta de destino logo abaixo dele, a pasta
    /// em foco acima do resto e, com um filtro, os destacados à frente dos esmaecidos. Como o
    /// esmaecido continua sólido, um cartão apagado por cima esconderia parte do destacado.
    func layer(for item: BoardItem, emphasis: Double? = nil) -> Double {
        if item.id == dragged { return 4 }
        if item.id == dropTarget { return 3 }
        if item.id == hoveredFolder { return 2 }
        return (emphasis ?? self.emphasis(for: item)) < 1 ? 0 : 1
    }
}
