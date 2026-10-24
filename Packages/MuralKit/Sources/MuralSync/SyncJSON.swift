import Foundation

/// O JSON de tudo que o MuralSync grava, nos campos do iCloud e no disco: chaves em ordem fixa e datas como o número de segundos
/// de referência, a mesma estratégia do `BoardRepository`.
///
/// O número mantém o valor exato de uma `Date` (um texto ISO-8601 sem frações perderia a precisão), e a ordem das chaves faz o mesmo
/// valor dar sempre os mesmos bytes. Cada chamada cria o seu codificador: `JSONEncoder` e `JSONDecoder` não são `Sendable`.
enum SyncJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return try decoder.decode(type, from: data)
    }
}
