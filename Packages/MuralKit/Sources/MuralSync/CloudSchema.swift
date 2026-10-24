import Foundation
import MuralKit

/// Os nomes que o Mural usa no iCloud: tipos de registro, zona de cada mural e chaves dos campos.
///
/// Tudo aqui já está gravado nos murais de quem sincroniza. Renomear um nome ou uma chave faz os Macs não se entenderem, então
/// só se acrescenta; os testes fixam os valores atuais.
public enum CloudSchema {
    /// Os tipos de registro de uma zona de mural.
    public enum RecordType: String, CaseIterable, Sendable {
        /// Um por zona: o nome e a versão do formato do mural.
        case mural = "Mural"
        /// Um por cartão, com o nome igual ao `id` do cartão.
        case card = "Card"
        /// Um por texto livre, com o nome igual ao `id` dele.
        case freeText = "FreeText"
        /// Um por arquivo de `Items/`, com o nome igual ao nome do arquivo.
        case mediaFile = "MediaFile"
    }

    /// O nome do registro do mural: há um só por zona.
    public static let muralRecordName = "mural"

    /// O começo do nome da zona de cada mural.
    private static let zonePrefix = "mural-"

    /// O nome da zona do mural no iCloud: uma zona por mural, para compartilhar um mural sem expor os outros.
    public static func zoneName(for id: BoardID) -> String {
        zonePrefix + id.rawValue.uuidString
    }

    /// O mural de uma zona, ou `nil` se o nome não é de zona de mural. Só vale o nome que `zoneName(for:)` produz: um nome com o
    /// mesmo UUID em outra caixa não volta para a mesma zona, então não é aceito.
    public static func boardID(fromZoneName name: String) -> BoardID? {
        guard name.hasPrefix(zonePrefix) else { return nil }
        let suffix = String(name.dropFirst(zonePrefix.count))
        guard let uuid = UUID(uuidString: suffix), uuid.uuidString == suffix else { return nil }
        return BoardID(rawValue: uuid)
    }

    /// As chaves dos campos dos registros; o valor de texto é o nome do campo no iCloud.
    public enum Key: String, CaseIterable, Sendable {
        // Cartão (o texto livre também usa `createdAt`, `x`, `y`, `width`, `height` e `text`).
        case kind, title, createdAt, parentID, x, y, layer, folderX, folderY, fileName, text, caption
        case stickyColor, colorTag, tag, checklist, imageMetadata, link, reminder, music, attachments
        case width, height
        // Cartão, texto livre e mural.
        case formatVersion
        // Mural.
        case name
        // Arquivo de mídia.
        case file, cardID
    }
}
