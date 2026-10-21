import Foundation

/// Metadados lidos do começo (`<head>`) de uma página HTML: título, resumo, nome do site, imagem e ícones.
///
/// A leitura é tolerante e não usa rede: examina só os primeiros 512 KB, para no `</head>` ou no primeiro
/// `<body` e nunca falha. HTML malformado ou dados quaisquer apenas deixam campos vazios.
public struct HTMLHeadMetadata: Equatable, Sendable {
    /// `og:title`, `twitter:title` ou `<title>`, nessa ordem.
    public var title: String?
    /// `og:description`, `twitter:description` ou `description`, nessa ordem; no máximo 300 caracteres.
    public var summary: String?
    /// `og:site_name`.
    public var siteName: String?
    /// Imagem de prévia (`og:image…` ou `twitter:image…`), absoluta e só `http` ou `https`.
    public var imageURL: URL?
    /// Ícones do site por ordem de preferência e sem repetidos. O `/favicon.ico` implícito não entra.
    public var iconURLs: [URL]

    public init(title: String? = nil, summary: String? = nil, siteName: String? = nil, imageURL: URL? = nil, iconURLs: [URL] = []) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.iconURLs = iconURLs
    }
}

extension HTMLHeadMetadata {
    /// Quantos bytes do início do documento são examinados.
    private static let byteLimit = 512 * 1024

    /// Lê os metadados de uma página.
    /// - Parameters:
    ///   - data: bytes da página; só os primeiros 512 KB são examinados.
    ///   - baseURL: endereço da página, base das URLs relativas quando não há `<base href>`.
    ///   - textEncodingName: codificação do cabeçalho HTTP (`utf-8`, `iso-8859-1`...); vale mais que o `<meta charset>`.
    public static func parse(_ data: Data, baseURL: URL, textEncodingName: String? = nil) -> HTMLHeadMetadata {
        let bytes = Array(data.prefix(byteLimit))
        let text = HeadDecoder.text(from: bytes, headerEncodingName: textEncodingName)
        var collector = HeadCollector()
        HeadScanner.scan(Array(text.utf8)) { collector.add($0) }
        return collector.metadata(baseURL: baseURL)
    }
}

// MARK: - Varredura

/// O que a varredura encontra no começo da página.
private enum HeadElement {
    /// `<meta>`, `<link>` ou `<base>`, com os atributos já sem entidades (nomes em minúsculas; vale a primeira ocorrência).
    case tag(name: String, attributes: [String: String])
    /// Texto do primeiro `<title>`, já sem entidades.
    case title(String)
}

/// Percorre os bytes de uma página à procura de `<meta>`, `<link>`, `<base>` e `<title>`.
///
/// Segue de perto o tokenizador do HTML, mas sem montar árvore: ignora comentários e o conteúdo de
/// `<script>` e `<style>`, aceita atributos com aspas duplas, simples ou sem aspas e para no `</head>`
/// ou no primeiro `<body`. Cada passo avança pelo menos um byte, então qualquer entrada termina.
private struct HeadScanner {
    private static let collected: Set<String> = ["meta", "link", "base"]
    private static let rawText: Set<String> = ["script", "style"]

    private let bytes: [UInt8]
    private var index = 0

    private init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func scan(_ bytes: [UInt8], visit: (HeadElement) -> Void) {
        var scanner = HeadScanner(bytes)
        scanner.run(visit)
    }

    private mutating func run(_ visit: (HeadElement) -> Void) {
        var sawTitle = false
        while let open = firstIndex(of: Byte.lessThan, from: index) {
            index = open + 1
            guard index < bytes.count else { return }
            let next = bytes[index]
            if next == Byte.bang {
                if bytes.count > index + 2, bytes[index + 1] == Byte.hyphen, bytes[index + 2] == Byte.hyphen {
                    // Comentário: vai até "-->"; se não fechar, engole o resto, como os navegadores.
                    guard let end = find(Byte.commentEnd, from: index + 1) else { return }
                    index = end + Byte.commentEnd.count
                } else {
                    skipPastTag()
                }
            } else if next == Byte.question {
                skipPastTag()
            } else if next == Byte.slash {
                index += 1
                if readName() == "head" { return }
                skipPastTag()
            } else if Byte.isLetter(next) {
                let name = readName()
                if name == "body" { return }
                let wanted = Self.collected.contains(name)
                let attributes = readAttributes(keep: wanted)
                if wanted {
                    visit(.tag(name: name, attributes: attributes))
                } else if Self.rawText.contains(name) {
                    // O conteúdo de script e style é texto puro: "<meta" ali dentro não é uma tag.
                    guard let close = find(Array("</\(name)".utf8), from: index) else { return }
                    index = close
                } else if name == "title", !sawTitle {
                    sawTitle = true
                    visit(.title(readTitleText()))
                }
            }
            // Qualquer outro byte depois de "<" é só texto.
        }
    }

    // MARK: Tags

    /// Lê o nome da tag, em minúsculas, até um espaço, "/" ou ">".
    private mutating func readName() -> String {
        let start = index
        while index < bytes.count, !Byte.isWhitespace(bytes[index]), bytes[index] != Byte.slash, bytes[index] != Byte.greaterThan {
            index += 1
        }
        return String(decoding: bytes[start..<index].map(Byte.lowercased), as: UTF8.self)
    }

    /// Lê os atributos até o ">" que fecha a tag. Com `keep` falso só avança, respeitando as aspas.
    private mutating func readAttributes(keep: Bool) -> [String: String] {
        var attributes: [String: String] = [:]
        while index < bytes.count {
            while index < bytes.count, Byte.isWhitespace(bytes[index]) || bytes[index] == Byte.slash { index += 1 }
            guard index < bytes.count else { break }
            if bytes[index] == Byte.greaterThan {
                index += 1
                break
            }

            // O primeiro byte sempre entra no nome: assim um "=" solto não trava a leitura.
            let nameStart = index
            index += 1
            while index < bytes.count, !Byte.isWhitespace(bytes[index]), bytes[index] != Byte.slash,
                bytes[index] != Byte.greaterThan, bytes[index] != Byte.equals
            {
                index += 1
            }
            let name = String(decoding: bytes[nameStart..<index].map(Byte.lowercased), as: UTF8.self)

            while index < bytes.count, Byte.isWhitespace(bytes[index]) { index += 1 }
            var value = ""
            if index < bytes.count, bytes[index] == Byte.equals {
                index += 1
                while index < bytes.count, Byte.isWhitespace(bytes[index]) { index += 1 }
                if index < bytes.count {
                    let quote = bytes[index]
                    if quote == Byte.doubleQuote || quote == Byte.singleQuote {
                        index += 1
                        let start = index
                        while index < bytes.count, bytes[index] != quote { index += 1 }
                        value = HeadEntities.decode(text(start..<index))
                        if index < bytes.count { index += 1 }
                    } else {
                        let start = index
                        while index < bytes.count, !Byte.isWhitespace(bytes[index]), bytes[index] != Byte.greaterThan { index += 1 }
                        value = HeadEntities.decode(text(start..<index))
                    }
                }
            }
            if keep, attributes[name] == nil { attributes[name] = value }
        }
        return attributes
    }

    /// Lê o texto do `<title>` até o `</title>`. Sem fecho, até a próxima tag.
    private mutating func readTitleText() -> String {
        let start = index
        let end = find(Byte.titleEnd, from: start) ?? firstIndex(of: Byte.lessThan, from: start) ?? bytes.count
        index = end
        return HeadEntities.decode(text(start..<end))
    }

    private mutating func skipPastTag() {
        index = firstIndex(of: Byte.greaterThan, from: index).map { $0 + 1 } ?? bytes.count
    }

    // MARK: Bytes

    private func text(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private func firstIndex(of byte: UInt8, from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes[start...].firstIndex(of: byte)
    }

    /// Primeira posição de `needle` (ASCII em minúsculas) a partir de `start`, sem diferenciar maiúsculas.
    private func find(_ needle: [UInt8], from start: Int) -> Int? {
        guard let first = needle.first, start >= 0, bytes.count - start >= needle.count else { return nil }
        for position in start...(bytes.count - needle.count) where Byte.lowercased(bytes[position]) == first {
            var offset = 1
            while offset < needle.count, Byte.lowercased(bytes[position + offset]) == needle[offset] { offset += 1 }
            if offset == needle.count { return position }
        }
        return nil
    }
}

private enum Byte {
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let slash = UInt8(ascii: "/")
    static let bang = UInt8(ascii: "!")
    static let question = UInt8(ascii: "?")
    static let equals = UInt8(ascii: "=")
    static let hyphen = UInt8(ascii: "-")
    static let doubleQuote = UInt8(ascii: "\"")
    static let singleQuote = UInt8(ascii: "'")
    static let commentEnd = Array("-->".utf8)
    static let titleEnd = Array("</title".utf8)

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (byte | 0x20) >= 0x61 && (byte | 0x20) <= 0x7A
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
    }
}

// MARK: - Codificação

private enum HeadDecoder {
    /// Codificações largas não cabem num `<meta>` lido como ASCII; nesse caso vale UTF-8, como nos navegadores.
    private static let wideEncodings: [String.Encoding] = [
        .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian,
    ]

    /// Decodifica a página pela primeira codificação que servir: cabeçalho HTTP, `<meta>` dos primeiros 4 KB,
    /// UTF-8 e, como último recurso, Latin-1 (que aceita qualquer sequência de bytes).
    static func text(from bytes: [UInt8], headerEncodingName: String?) -> String {
        var declared: [String.Encoding] = []
        if let name = headerEncodingName, let encoding = encoding(named: name) { declared.append(encoding) }
        if let name = metaCharset(in: bytes), let encoding = encoding(named: name) {
            declared.append(wideEncodings.contains(encoding) ? .utf8 : encoding)
        }

        let data = Data(bytes)
        for encoding in declared {
            switch encoding {
            case .utf8:
                // Declarado, o UTF-8 vale mesmo com bytes soltos inválidos: eles viram "�" sem trocar a codificação.
                return String(decoding: bytes, as: UTF8.self)
            case .isoLatin1, .ascii:
                // Na web, "iso-8859-1" e "us-ascii" significam windows-1252: aspas e travessões ocupam 0x80 a 0x9F.
                if let text = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) { return text }
            default:
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }

        // O corte nos 512 KB pode ter partido o último caractere: aceita até 3 bytes soltos no fim.
        for dropped in 0...min(3, bytes.count) {
            if let text = String(data: Data(bytes.dropLast(dropped)), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Nome da codificação declarada em `<meta charset>` ou `<meta http-equiv="Content-Type">` nos primeiros 4 KB.
    private static func metaCharset(in bytes: [UInt8]) -> String? {
        var found: String?
        HeadScanner.scan(Array(bytes.prefix(4096))) { element in
            guard found == nil, case .tag(let name, let attributes) = element, name == "meta" else { return }
            if let charset = attributes["charset"] {
                found = charset
            } else if attributes["http-equiv"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-type",
                let content = attributes["content"]
            {
                found = charset(inContentType: content)
            }
        }
        return found
    }

    /// Extrai `iso-8859-1` de `text/html; charset=iso-8859-1`.
    private static func charset(inContentType content: String) -> String? {
        let lowered = content.lowercased()
        guard let range = lowered.range(of: "charset") else { return nil }
        var rest = lowered[range.upperBound...].drop(while: \.isWhitespace)
        guard rest.first == "=" else { return nil }
        rest = rest.dropFirst().drop(while: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
        let name = rest.prefix(while: { !$0.isWhitespace && $0 != ";" && $0 != "\"" && $0 != "'" })
        return name.isEmpty ? nil : String(name)
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let quotes = CharacterSet(charactersIn: "\"'")
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(quotes))
        guard !trimmed.isEmpty else { return nil }
        let encoding = CFStringConvertIANACharSetNameToEncoding(trimmed as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}

// MARK: - Entidades

private enum HeadEntities {
    /// Nomes das entidades de `U+00A0` a `U+00FF`, na ordem dos códigos (letras acentuadas do português incluídas).
    private static let latin1Names = [
        "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
        "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34",
        "iquest", "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml", "Igrave",
        "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute",
        "Ucirc", "Uuml", "Yacute", "THORN", "szlig", "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave",
        "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml",
        "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
    ]

    private static let named: [String: Unicode.Scalar] = {
        var table: [String: Unicode.Scalar] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
            "bull": "\u{2022}", "hellip": "\u{2026}", "euro": "\u{20AC}", "trade": "\u{2122}",
        ]
        for (offset, name) in latin1Names.enumerated() {
            table[name] = Unicode.Scalar(UInt8(0xA0 + offset))
        }
        return table
    }()

    /// Troca `&amp;`, `&eacute;`, `&#233;` e `&#xE9;` pelos caracteres. O que não for entidade conhecida fica como está.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var position = 0
        while position < scalars.count {
            if scalars[position] == "&", let (scalar, length) = entity(in: scalars, at: position) {
                result.append(scalar)
                position += length
            } else {
                result.append(scalars[position])
                position += 1
            }
        }
        return String(result)
    }

    /// Entidade que começa em `start` (no "&"): o caractere e quantos scalars ela ocupa, com o ";".
    private static func entity(in scalars: [Unicode.Scalar], at start: Int) -> (Unicode.Scalar, Int)? {
        // A maior entidade aceita, "&#x10FFFF;", tem 10 scalars.
        let limit = min(scalars.count, start + 12)
        guard let semicolon = (start + 1..<limit).first(where: { scalars[$0] == ";" }) else { return nil }
        let body = String(String.UnicodeScalarView(scalars[start + 1..<semicolon]))
        let length = semicolon - start + 1
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let isHex = digits.first == "x" || digits.first == "X"
            guard let code = UInt32(isHex ? digits.dropFirst() : digits, radix: isHex ? 16 : 10), code != 0,
                let scalar = Unicode.Scalar(code)
            else { return nil }
            return (scalar, length)
        }
        return named[body].map { ($0, length) }
    }
}

// MARK: - Coleta

/// Junta o que a varredura encontrou e escolhe, por precedência, o valor de cada campo.
private struct HeadCollector {
    private struct Icon {
        let href: String
        /// 0 para `apple-touch-icon`, 1 para `icon` e 2 para `shortcut icon`.
        let tier: Int
        /// Maior lado declarado em `sizes`; `nil` sem tamanho ou com `any`.
        let side: Int?
        let order: Int
    }

    private static let maximumTextLength = 300

    /// Valor de `content` de cada `<meta>` por `property` ou `name` em minúsculas; vale o primeiro não vazio.
    private var metas: [String: String] = [:]
    private var titleText: String?
    private var baseHref: String?
    private var icons: [Icon] = []

    mutating func add(_ element: HeadElement) {
        switch element {
        case .title(let text):
            titleText = titleText ?? text
        case .tag(let name, let attributes):
            switch name {
            case "meta": addMeta(attributes)
            case "link": addLink(attributes)
            case "base":
                if baseHref == nil, let href = attributes["href"], !Self.trimmed(href).isEmpty { baseHref = href }
            default: break
            }
        }
    }

    private mutating func addMeta(_ attributes: [String: String]) {
        guard let content = attributes["content"], !Self.trimmed(content).isEmpty else { return }
        for attribute in ["property", "name"] {
            guard let key = attributes[attribute].map({ Self.trimmed($0).lowercased() }), !key.isEmpty else { continue }
            metas[key] = metas[key] ?? content
        }
    }

    private mutating func addLink(_ attributes: [String: String]) {
        guard let href = attributes["href"], !Self.trimmed(href).isEmpty else { return }
        let tokens = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let tier: Int
        if tokens.contains("apple-touch-icon") || tokens.contains("apple-touch-icon-precomposed") {
            tier = 0
        } else if tokens.contains("icon") {
            tier = tokens.contains("shortcut") ? 2 : 1
        } else {
            return
        }
        icons.append(Icon(href: href, tier: tier, side: Self.largestSide(in: attributes["sizes"]), order: icons.count))
    }

    func metadata(baseURL: URL) -> HTMLHeadMetadata {
        var base = baseURL
        if let baseHref, let resolved = Self.resolve(baseHref, against: baseURL) { base = resolved }
        return HTMLHeadMetadata(
            title: text(["og:title", "twitter:title"], fallback: titleText),
            summary: text(["og:description", "twitter:description", "description"]),
            siteName: text(["og:site_name"]),
            imageURL: imageURL(base: base),
            iconURLs: iconURLs(base: base)
        )
    }

    // MARK: Escolha

    private func text(_ keys: [String], fallback: String? = nil) -> String? {
        for candidate in keys.map({ metas[$0] }) + [fallback] {
            if let text = Self.normalized(candidate) { return Self.limited(text, to: Self.maximumTextLength) }
        }
        return nil
    }

    private func imageURL(base: URL) -> URL? {
        for key in ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"] {
            if let value = metas[key], let url = Self.resolve(value, against: base) { return url }
        }
        return nil
    }

    /// `apple-touch-icon` antes de `icon` e esse antes de `shortcut icon`; em cada grupo, o maior `sizes` primeiro e,
    /// sem tamanho, a ordem do documento.
    private func iconURLs(base: URL) -> [URL] {
        let ordered = icons.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            switch (lhs.side, rhs.side) {
            case (let left?, let right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.order < rhs.order
            }
        }
        var seen = Set<URL>()
        return ordered.compactMap { icon in
            guard let url = Self.resolve(icon.href, against: base), seen.insert(url).inserted else { return nil }
            return url
        }
    }

    // MARK: Texto e endereços

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Colapsa espaços e quebras (inclusive o espaço sem quebra) em um espaço e apara as pontas; vazio vira `nil`.
    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Corta em fronteira de palavra para caber em `limit` caracteres contando a reticência final.
    private static func limited(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        var end = text.index(text.startIndex, offsetBy: limit - 1)
        if !text[end].isWhitespace, let space = text[..<end].lastIndex(where: \.isWhitespace) { end = space }
        return text[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Maior lado entre os tamanhos de `sizes` (`"16x16 32x32"`); `nil` se não houver nenhum válido.
    private static func largestSide(in sizes: String?) -> Int? {
        var best: Int?
        for token in (sizes ?? "").lowercased().split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "x", omittingEmptySubsequences: false)
            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else { continue }
            best = max(best ?? 0, width, height)
        }
        return best
    }

    /// Endereço absoluto de `reference` em relação a `base`; `nil` se vazio, inválido ou fora de `http` e `https`.
    private static func resolve(_ reference: String, against base: URL) -> URL? {
        let cleaned = trimmed(reference.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        guard !cleaned.isEmpty, let url = URL(string: cleaned, relativeTo: base)?.absoluteURL, WebLink.isWeb(url) else { return nil }
        return url
    }
}
