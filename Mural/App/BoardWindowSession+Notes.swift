import Foundation
import MuralKit

extension BoardWindowSession {
    /// Cria um cartão de texto com a nota do editor: o Markdown, os cartões embutidos que ele cita e cada imagem, como anexos.
    ///
    /// A ordem importa: primeiro as imagens são gravadas em `Items/` (ainda sem citação), depois o Markdown final é montado, com
    /// a linha provisória de cada imagem trocada pela linha final e a de uma imagem que não pôde ser gravada tirada, e só então o
    /// cartão é criado, uma vez só, já com o texto pronto e os anexos. O texto gravado nunca tem `mural-colando:`.
    ///
    /// Se a janela fecha enquanto as imagens são gravadas, nada é criado e os arquivos gravados são apagados. Uma troca de aba no
    /// meio não interrompe (só o fechamento). O título vem do texto (`ContentClassifier.title(forText:)`, que não usa linhas de
    /// imagem). Uma imagem perdida deixa "Uma imagem não pôde ser colada." em `lastError` do modelo.
    /// - Returns: o id do cartão; `nil`, sem criar nada, se o mural não aceita edição, fechou no meio ou o texto não virou cartão.
    @discardableResult
    func importNote(_ note: PastedNote, at anchor: BoardPoint? = nil) async -> UUID? {
        guard canEdit, let model else { return nil }

        // As imagens citadas, na ordem em que aparecem no texto.
        let cited = note.images.keys
            .compactMap { token in note.text.range(of: NoteImageMarkup.pendingLine(token: token)).map { (token, $0.lowerBound) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        var stored: [(token: UUID, attachment: NoteAttachment?)] = []
        for token in cited {
            guard let source = note.images[token] else { continue }
            stored.append((token, await storeNoteImage(source, model)))
        }
        let attachments = stored.compactMap(\.attachment)
        guard !isClosed, self.model === model else {
            for attachment in attachments { model.discardNoteImage(attachment) }
            return nil
        }

        var text = note.text
        for entry in stored {
            let line = entry.attachment.map { NoteImageMarkup.line(fileName: $0.fileName) } ?? ""
            text = NoteImageMarkup.replacingPending(entry.token, with: line, in: text) ?? text
        }
        guard let item = model.importText(text, as: .text, into: nil, at: anchor) else {
            for attachment in attachments { model.discardNoteImage(attachment) }
            model.lastError = "O texto não pôde virar um cartão."
            return nil
        }
        for attachment in attachments { model.addNoteAttachment(attachment, to: item.id) }
        for id in NoteImageMarkup.referencedCardIDs(in: text) {
            guard let card = note.embeds[id] else { continue }
            let attachment = NoteAttachment(
                fileName: NoteImageMarkup.cardAttachmentName(for: id), pixelWidth: 0, pixelHeight: 0, card: card)
            model.addNoteAttachment(attachment, to: item.id)
        }
        if stored.contains(where: { $0.attachment == nil }) { model.lastError = "Uma imagem não pôde ser colada." }
        captureBoardIfNeeded()
        return item.id
    }
}
