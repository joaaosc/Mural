import Foundation
import Testing

@testable import MuralKit

@Suite("Proporções e encaixe do canto de uma foto")
struct ImageProportionTests {
    // MARK: Apoio

    /// Foto com as medidas do arquivo, quando dadas, e o tamanho escolhido, quando há.
    private func photo(pixels: (width: Int, height: Int)? = (4000, 3000), size: BoardSize? = nil) -> BoardItem {
        let metadata = pixels.map {
            ImageMetadata(pixelWidth: $0.width, pixelHeight: $0.height, fileSizeBytes: 1, colorProfile: nil, palette: [])
        }
        return BoardItem(kind: .image, title: "Foto", imageMetadata: metadata, size: size)
    }

    private func size(_ width: Double, _ height: Double) -> BoardSize {
        BoardSize(width: width, height: height)
    }

    // MARK: Lista de proporções

    @Test("A proporção da foto vem primeiro e toma o lugar da fixa igual a ela")
    func originalReplacesEqualPreset() {
        let proportions = BoardLayout.imageProportions(for: photo())
        #expect(proportions.first == .original)
        #expect(!proportions.contains(.fixed(width: 4, height: 3)))
        #expect(proportions.count == BoardLayout.imageProportionPresets.count)
    }

    @Test("Sem as medidas do arquivo, só as proporções fixas")
    func presetsWithoutMetadata() {
        #expect(BoardLayout.imageProportions(for: photo(pixels: nil)) == BoardLayout.imageProportionPresets)
    }

    @Test("Duas proporções vizinhas nunca encaixam no mesmo ponto: sobra faixa livre entre elas")
    func snapZonesDoNotOverlap() {
        let ratios = BoardLayout.imageProportionPresets.map { BoardLayout.ratio(of: $0, for: photo()) }.sorted()
        let snap = log(1 + BoardLayout.imageProportionSnap)
        for (lower, upper) in zip(ratios, ratios.dropFirst()) {
            #expect(log(upper / lower) > 2 * snap, "\(lower) e \(upper)")
        }
    }

    // MARK: Arrasto do canto

    @Test("Perto da proporção da foto, o arrasto encaixa nela e o lado que mais andou manda")
    func snapsToOriginal() {
        let result = BoardLayout.resizedImageSize(of: photo(), deltaWidth: 100, deltaHeight: 0)
        #expect(result.proportion == .original)
        #expect(result.size == size(250, 188))
    }

    @Test("Com a altura andando mais, a largura é que se ajusta ao encaixe")
    func heightLeadsTheSnap() {
        let result = BoardLayout.resizedImageSize(of: photo(), deltaWidth: 0, deltaHeight: -40)
        #expect(result.proportion == .fixed(width: 1, height: 1))
        #expect(result.size == size(150, 150))
    }

    @Test("Longe de qualquer proporção, o canto acompanha o ponteiro")
    func freeBetweenProportions() {
        let result = BoardLayout.resizedImageSize(of: photo(), deltaWidth: 60, deltaHeight: 60)
        #expect(result.proportion == nil)
        #expect(result.size == size(210, 250))
    }

    @Test("Com Shift vale a proporção do tamanho de partida, sem encaixe")
    func keepingProportionSkipsSnap() {
        let item = photo()
        let result = BoardLayout.resizedImageSize(of: item, deltaWidth: 100, deltaHeight: 0, keepingProportion: true)
        #expect(result.proportion == nil)
        #expect(result.size == BoardLayout.resizedSize(of: item, deltaWidth: 100, deltaHeight: 0, keepingProportion: true))
    }

    @Test("No limite mínimo, o encaixe cresce os dois lados juntos em vez de desmanchar a proporção")
    func snapRespectsMinimum() {
        let result = BoardLayout.resizedImageSize(of: photo(pixels: nil, size: size(60, 100)), deltaWidth: 0, deltaHeight: 5)
        #expect(result.proportion == .fixed(width: 9, height: 16))
        #expect(result.size == size(60, 107))
    }

    @Test("No limite máximo, o encaixe encolhe os dois lados juntos em vez de desmanchar a proporção")
    func snapRespectsMaximum() {
        let result = BoardLayout.resizedImageSize(of: photo(pixels: nil, size: size(300, 700)), deltaWidth: 110, deltaHeight: 20)
        #expect(result.proportion == .fixed(width: 9, height: 16))
        #expect(result.size == size(405, 720))
    }

    @Test("Um cartão que não é foto não encaixa")
    func onlyPhotosSnap() {
        let sticky = BoardItem(kind: .sticky, title: "Post-it")
        let result = BoardLayout.resizedImageSize(of: sticky, deltaWidth: 0, deltaHeight: 0)
        #expect(result.proportion == nil)
        #expect(result.size == BoardLayout.resizedSize(of: sticky, deltaWidth: 0, deltaHeight: 0))
    }

    // MARK: Menu "Tamanho"

    @Test("A proporção do menu mantém o lado maior do tamanho atual")
    func menuSizeKeepsLongestSide() {
        let item = photo()
        #expect(BoardLayout.imageSize(for: item, in: .original) == size(190, 143))
        #expect(BoardLayout.imageSize(for: item, in: .fixed(width: 1, height: 1)) == size(190, 190))
        #expect(BoardLayout.imageSize(for: item, in: .fixed(width: 9, height: 16)) == size(107, 190))
        #expect(BoardLayout.imageSize(for: BoardItem(kind: .sticky, title: "Post-it"), in: .original) == nil)
    }

    @Test("A proporção atual é reconhecida apesar do arredondamento, e o tamanho padrão não tem nenhuma")
    func currentProportion() {
        #expect(BoardLayout.imageProportion(of: photo(size: size(190, 143))) == .original)
        #expect(BoardLayout.imageProportion(of: photo(size: size(160, 90))) == .fixed(width: 16, height: 9))
        #expect(BoardLayout.imageProportion(of: photo()) == nil)
    }
}
