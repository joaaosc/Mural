import CoreGraphics

/// Faixa de um cartão na pasta: mídia à esquerda, notas e listas à direita.
nonisolated enum GalleryLane: Sendable {
    case media
    case notes
}

/// Geometria da pasta, separada da view para poder ser testada.
///
/// Cada faixa usa só as colunas de que precisa (nunca mais colunas que cartões) e
/// cada coluna tem largura máxima; a composição fica centralizada. Assim, poucos
/// itens ficam lado a lado em vez de espalhados por colunas vazias.
nonisolated struct GalleryArrangement {
    struct Metrics {
        var spacing: CGFloat = 16
        var laneSpacing: CGFloat = 32
        /// Colunas de uma faixa quando ela está sozinha na pasta.
        var maxColumnsAlone = 4
        var maxMediaColumns = 3
        var maxNoteColumns = 2
        var maxColumnWidth: CGFloat = 300
        var minColumnWidth: CGFloat = 60
        /// Notas são mais estreitas que fotos, como no conceito.
        var noteWidthRatio: CGFloat = 0.6
    }

    let frames: [CGRect]
    let size: CGSize

    /// - Parameters:
    ///   - width: largura disponível.
    ///   - lanes: faixa de cada cartão, na ordem de exibição.
    ///   - heightForWidth: altura do cartão de índice `i` para uma largura de coluna.
    init(width: CGFloat, lanes: [GalleryLane], metrics: Metrics = .init(), heightForWidth: (Int, CGFloat) -> CGFloat) {
        self.init(width: width, laneCount: lanes.count, laneAt: { lanes[$0] }, metrics: metrics, heightForWidth: heightForWidth)
    }

    /// Variante para consumidores que já têm as faixas nos subviews: evita materializar um array intermediário.
    init(
        width: CGFloat,
        laneCount: Int,
        laneAt: (Int) -> GalleryLane,
        metrics: Metrics = .init(),
        heightForWidth: (Int, CGFloat) -> CGFloat
    ) {
        // Partition in one pass. The arrangement is rebuilt while the collection
        // layout cache is invalidated, so avoid the two closure-based traversals
        // and temporary intermediate storage created by `filter`.
        var mediaIndices: [Int] = []
        var noteIndices: [Int] = []
        mediaIndices.reserveCapacity(laneCount / 2)
        noteIndices.reserveCapacity(laneCount / 2)
        for index in 0..<laneCount {
            switch laneAt(index) {
            case .media:
                mediaIndices.append(index)
            case .notes:
                noteIndices.append(index)
            }
        }
        let hasBothLanes = !mediaIndices.isEmpty && !noteIndices.isEmpty

        let mediaColumns = min(mediaIndices.count, hasBothLanes ? metrics.maxMediaColumns : metrics.maxColumnsAlone)
        let noteColumns = min(noteIndices.count, hasBothLanes ? metrics.maxNoteColumns : metrics.maxColumnsAlone)

        let gaps =
            CGFloat(max(mediaColumns - 1, 0) + max(noteColumns - 1, 0)) * metrics.spacing
            + (hasBothLanes ? metrics.laneSpacing : 0)
        let units = CGFloat(mediaColumns) + CGFloat(noteColumns) * metrics.noteWidthRatio
        let unit = units > 0 ? min(metrics.maxColumnWidth, max((width - gaps) / units, metrics.minColumnWidth)) : 0
        let usedWidth = units * unit + gaps

        var frames = Array(repeating: CGRect.zero, count: laneCount)
        let originX = max((width - usedWidth) / 2, 0)

        let mediaHeight = Self.placeMasonry(
            indices: mediaIndices, columns: mediaColumns, columnWidth: unit, originX: originX,
            spacing: metrics.spacing, heightForWidth: heightForWidth, frames: &frames)

        let notesOriginX =
            originX + (mediaColumns > 0 ? CGFloat(mediaColumns) * unit + CGFloat(mediaColumns - 1) * metrics.spacing : 0)
            + (hasBothLanes ? metrics.laneSpacing : 0)
        let notesHeight = Self.placeMasonry(
            indices: noteIndices, columns: noteColumns, columnWidth: unit * metrics.noteWidthRatio, originX: notesOriginX,
            spacing: metrics.spacing, heightForWidth: heightForWidth, frames: &frames)

        self.frames = frames
        self.size = CGSize(width: width, height: max(mediaHeight, notesHeight))
    }

    /// Coloca cada cartão na coluna mais curta da faixa e devolve a altura da faixa.
    private static func placeMasonry(
        indices: [Int], columns: Int, columnWidth: CGFloat, originX: CGFloat, spacing: CGFloat,
        heightForWidth: (Int, CGFloat) -> CGFloat, frames: inout [CGRect]
    ) -> CGFloat {
        guard columns > 0 else { return 0 }
        var heights = Array(repeating: CGFloat.zero, count: columns)
        for index in indices {
            var column = 0
            if columns > 1 {
                for candidate in 1..<heights.count where heights[candidate] < heights[column] {
                    column = candidate
                }
            }
            let height = heightForWidth(index, columnWidth)
            frames[index] = CGRect(
                x: originX + CGFloat(column) * (columnWidth + spacing), y: heights[column], width: columnWidth, height: height)
            heights[column] += height + spacing
        }
        return max((heights.max() ?? 0) - spacing, 0)
    }
}
