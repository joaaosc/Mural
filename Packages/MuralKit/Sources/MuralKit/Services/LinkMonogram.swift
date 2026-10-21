/// Letra e matiz do monograma que representa um site no cartão de link quando não há imagem de prévia.
public enum LinkMonogram {
    private static let fnvOffsetBasis: UInt32 = 2_166_136_261
    private static let fnvPrime: UInt32 = 16_777_619

    /// A primeira letra ou número do host, em maiúscula; `•` se o host não tiver nenhum.
    ///
    /// Sempre um único caractere: `ß`, que vira `SS` em maiúscula, resulta em `S`.
    public static func letter(for host: String) -> String {
        guard let first = host.first(where: { $0.isLetter || $0.isNumber }),
            let letter = first.uppercased().first
        else { return "•" }
        return String(letter)
    }

    /// Matiz do host, de 0 (incluso) a 1 (excluso), sempre o mesmo para o mesmo host.
    ///
    /// É o hash FNV-1a de 32 bits dos bytes UTF-8 do host em minúsculas, e não `hashValue`, que muda
    /// a cada execução do app. Maiúsculas e minúsculas não mudam o resultado, porque o host não as distingue.
    public static func hue(for host: String) -> Double {
        var hash = fnvOffsetBasis
        for byte in host.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* fnvPrime
        }
        return Double(hash) / 4_294_967_296
    }
}
