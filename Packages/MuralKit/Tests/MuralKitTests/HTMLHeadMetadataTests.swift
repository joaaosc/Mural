import Foundation
import Testing

@testable import MuralKit

@Suite("Metadados do começo da página")
struct HTMLHeadMetadataTests {
    private func parse(
        _ html: String, base: String = "https://example.com/blog/post.html", encoding: String? = nil
    ) throws -> HTMLHeadMetadata {
        try parse(Data(html.utf8), base: base, encoding: encoding)
    }

    private func parse(
        _ data: Data, base: String = "https://example.com/blog/post.html", encoding: String? = nil
    ) throws -> HTMLHeadMetadata {
        HTMLHeadMetadata.parse(data, baseURL: try #require(URL(string: base)), textEncodingName: encoding)
    }

    /// Página completa com `inner` dentro do `<head>`.
    private func page(_ inner: String) -> String {
        "<!DOCTYPE html><html><head>\(inner)</head><body><p>texto</p></body></html>"
    }

    private func bytes(_ parts: [[UInt8]]) -> Data {
        Data(parts.flatMap { $0 })
    }

    // MARK: Precedência

    @Test(
        "Título: og:title, depois twitter:title, depois <title>, qualquer que seja a ordem no documento",
        arguments: [
            (##"<title>Doc</title><meta name="twitter:title" content="Twitter"><meta property="og:title" content="OG">"##, "OG"),
            (##"<meta property="og:title" content="OG"><meta name="twitter:title" content="Twitter"><title>Doc</title>"##, "OG"),
            (##"<title>Doc</title><meta name="twitter:title" content="Twitter">"##, "Twitter"),
            (##"<title>Doc</title>"##, "Doc"),
            (##"<meta property="og:title" content="   "><meta name="twitter:title" content=""><title>Doc</title>"##, "Doc"),
            (##"<meta property="og:title"><title>Doc</title>"##, "Doc"),
        ])
    func titlePrecedence(inner: String, expected: String) throws {
        #expect(try parse(page(inner)).title == expected)
    }

    @Test(
        "Resumo: og:description, depois twitter:description, depois description",
        arguments: [
            (
                ##"<meta name="description" content="Meta"><meta name="twitter:description" content="Twitter"><meta property="og:description" content="OG">"##,
                "OG"
            ),
            (##"<meta name="description" content="Meta"><meta name="twitter:description" content="Twitter">"##, "Twitter"),
            (##"<meta name="description" content="Meta">"##, "Meta"),
            (##"<meta property="og:description" content=" "><meta name="description" content="Meta">"##, "Meta"),
        ])
    func summaryPrecedence(inner: String, expected: String) throws {
        #expect(try parse(page(inner)).summary == expected)
    }

    @Test("Nome do site vem de og:site_name e só dele")
    func siteName() throws {
        #expect(try parse(page(##"<meta property="og:site_name" content="Apple">"##)).siteName == "Apple")
        #expect(try parse(page(##"<meta name="application-name" content="App"><meta name="author" content="Eu">"##)).siteName == nil)
    }

    @Test(
        "Imagem: secure_url, og:image, og:image:url, twitter:image, twitter:image:src, qualquer que seja a ordem",
        arguments: [
            (
                ##"<meta name="twitter:image:src" content="/5.png"><meta name="twitter:image" content="/4.png"><meta property="og:image:url" content="/3.png"><meta property="og:image" content="/2.png"><meta property="og:image:secure_url" content="/1.png">"##,
                "https://example.com/1.png"
            ),
            (
                ##"<meta name="twitter:image:src" content="/5.png"><meta name="twitter:image" content="/4.png"><meta property="og:image:url" content="/3.png"><meta property="og:image" content="/2.png">"##,
                "https://example.com/2.png"
            ),
            (
                ##"<meta name="twitter:image:src" content="/5.png"><meta name="twitter:image" content="/4.png"><meta property="og:image:url" content="/3.png">"##,
                "https://example.com/3.png"
            ),
            (
                ##"<meta name="twitter:image:src" content="/5.png"><meta name="twitter:image" content="/4.png">"##,
                "https://example.com/4.png"
            ),
            (##"<meta name="twitter:image:src" content="/5.png">"##, "https://example.com/5.png"),
            (##"<meta property="og:image" content=""><meta name="twitter:image" content="/4.png">"##, "https://example.com/4.png"),
        ])
    func imagePrecedence(inner: String, expected: String) throws {
        #expect(try parse(page(inner)).imageURL?.absoluteString == expected)
    }

    @Test("A primeira ocorrência não vazia de cada chave vale")
    func firstNonBlankOccurrenceWins() throws {
        let metadata = try parse(
            page(
                ##"<meta property="og:title" content=""><meta property="og:title" content="Primeiro"><meta property="og:title" content="Segundo"><title>Um</title><title>Dois</title>"##
            ))
        #expect(metadata.title == "Primeiro")
        #expect(try parse(page("<title>Um</title><title>Dois</title>")).title == "Um")
    }

    // MARK: property e name

    @Test(
        "As chaves og: e twitter: valem em property e em name",
        arguments: [
            (##"<meta property="og:title" content="X">"##, "X"),
            (##"<meta name="og:title" content="X">"##, "X"),
            (##"<meta property="twitter:title" content="X">"##, "X"),
            (##"<meta name="twitter:title" content="X">"##, "X"),
            (##"<meta name="twitter:title" property="og:title" content="X">"##, "X"),
            (##"<meta property=" og:title " content="X">"##, "X"),
        ])
    func propertyAndNameBothWork(inner: String, expected: String) throws {
        #expect(try parse(page(inner)).title == expected)
    }

    @Test("Imagem e resumo também aceitam property e name")
    func propertyAndNameForOtherKeys() throws {
        let metadata = try parse(page(##"<meta name="og:image" content="/a.png"><meta property="description" content="Resumo">"##))
        #expect(metadata.imageURL?.absoluteString == "https://example.com/a.png")
        #expect(metadata.summary == "Resumo")
    }

    // MARK: Sintaxe tolerante

    @Test(
        "Aspas duplas, simples ou ausentes, caixa qualquer, quebras de linha e tag fechada com barra",
        arguments: [
            ##"<meta property="og:title" content="Aspas">"##,
            "<meta property='og:title' content='Aspas'>",
            "<meta property=og:title content=Aspas>",
            "<META PROPERTY=\"OG:TITLE\" CONTENT=\"Aspas\">",
            "<Meta Property='Og:Title' Content=Aspas>",
            "<meta\n  content=\"Aspas\"\n  property=\"og:title\"\n>",
            "<meta\tproperty=\"og:title\"\tcontent=\"Aspas\"\t/>",
            "<meta property=\"og:title\"content=\"Aspas\">",
            "<meta property=\"og:title\" content=\"Aspas\"/>",
            "<meta property = \"og:title\" content = 'Aspas' >",
            "<meta data-x=1 property=\"og:title\" lixo content=\"Aspas\" =solto>",
        ])
    func tolerantSyntax(inner: String) throws {
        #expect(try parse(page(inner)).title == "Aspas")
    }

    @Test("Aspas e sinal de maior dentro do valor não encerram a tag")
    func quotesInsideValues() throws {
        #expect(try parse(page(##"<meta property="og:title" content="a > b e L'Oréal">"##)).title == "a > b e L'Oréal")
        #expect(try parse(page(##"<meta property="og:title" content='diz "oi" > tchau'>"##)).title == #"diz "oi" > tchau"#)
    }

    @Test("<title> aceita atributos, caixa qualquer e entidades; o primeiro vale")
    func titleElement() throws {
        #expect(try parse(page(##"<TITLE lang="pt">Olá &amp; tchau</TITLE>"##)).title == "Olá & tchau")
        #expect(try parse(page("<title>\n  Linha 1\n\t  Linha 2  \n</title>")).title == "Linha 1 Linha 2")
        // O conteúdo do <title> é texto: "<b>" ali não vira tag.
        #expect(try parse(page("<title>a <b>negrito</b> b</title>")).title == "a <b>negrito</b> b")
    }

    @Test("<title> sem fecho vai até a próxima tag, que continua sendo lida")
    func unterminatedTitle() throws {
        let metadata = try parse("<head><title>Sem fecho<meta property=\"og:site_name\" content=\"Site\"></head>")
        #expect(metadata.title == "Sem fecho")
        #expect(metadata.siteName == "Site")
    }

    // MARK: Entidades

    @Test(
        "Entidades nomeadas e numéricas são decodificadas, uma vez só",
        arguments: [
            ("Tom &amp; Jerry", "Tom & Jerry"),
            ("1 &lt; 2 &gt; 0", "1 < 2 > 0"),
            ("&quot;aspas&quot; e &apos;simples&apos; e &#39;outra&#39;", "\"aspas\" e 'simples' e 'outra'"),
            ("A&nbsp;B", "A B"),
            ("caf&#233; caf&#xE9; caf&#XE9;", "café café café"),
            ("&#65;&#x42;&#x1F600;", "AB😀"),
            ("a&ccedil;&atilde;o &Eacute;&uacute; &ntilde;", "ação Éú ñ"),
            ("&ndash; &mdash; &hellip; &rsquo; &euro;", "– — … ’ €"),
            ("&amp;lt;", "&lt;"),
            ("&amp;amp;", "&amp;"),
        ])
    func entitiesAreDecoded(raw: String, expected: String) throws {
        #expect(try parse(page("<meta property=\"og:title\" content=\"\(raw)\">")).title == expected)
        #expect(try parse(page("<title>\(raw)</title>")).title == expected)
    }

    @Test(
        "O que não é entidade conhecida fica como está",
        arguments: [
            "AT&T", "Q&A: tudo", "&desconhecida;", "&amp", "& amp;", "&#;", "&#x;", "&#xZZ;", "&#0;", "&#xD800;", "&#1114112;", "&;",
            "&#99999999999;",
        ])
    func unknownEntitiesStay(raw: String) throws {
        #expect(try parse(page("<meta property=\"og:title\" content=\"\(raw)\">")).title == raw)
    }

    @Test("Entidades em endereços também são decodificadas")
    func entitiesInURLs() throws {
        let metadata = try parse(
            page(##"<meta property="og:image" content="/i.png?a=1&amp;b=2"><link rel="icon" href="/f.png?x=1&amp;y=2">"##))
        #expect(metadata.imageURL?.absoluteString == "https://example.com/i.png?a=1&b=2")
        #expect(metadata.iconURLs.map(\.absoluteString) == ["https://example.com/f.png?x=1&y=2"])
    }

    // MARK: Endereços

    @Test(
        "Endereços relativos são resolvidos contra o endereço da página",
        arguments: [
            ("/img/a.png", "https://example.com/img/a.png"),
            ("a.png", "https://example.com/blog/a.png"),
            ("./a.png", "https://example.com/blog/a.png"),
            ("../a.png", "https://example.com/a.png"),
            ("//cdn.example.net/a.png", "https://cdn.example.net/a.png"),
            ("a.png?x=1", "https://example.com/blog/a.png?x=1"),
            ("  /com-espacos.png \n", "https://example.com/com-espacos.png"),
            ("https://outro.com/a.png", "https://outro.com/a.png"),
            ("http://outro.com/a.png", "http://outro.com/a.png"),
        ])
    func relativeURLs(reference: String, expected: String) throws {
        let metadata = try parse(page("<meta property=\"og:image\" content=\"\(reference)\">"))
        #expect(metadata.imageURL?.absoluteString == expected)
    }

    @Test("<base href> vale para todos os endereços, mesmo os que vêm antes dele")
    func baseHref() throws {
        let metadata = try parse(
            page(
                ##"<meta property="og:image" content="capa.png"><link rel="icon" href="/icone.png"><base href="https://cdn.example.org/assets/">"##
            ))
        #expect(metadata.imageURL?.absoluteString == "https://cdn.example.org/assets/capa.png")
        #expect(metadata.iconURLs.map(\.absoluteString) == ["https://cdn.example.org/icone.png"])
    }

    @Test(
        "<base href> relativo é resolvido contra a página; o inválido ou sem href é ignorado e só o primeiro vale",
        arguments: [
            (##"<base href="/static/"><meta property="og:image" content="a.png">"##, "https://example.com/static/a.png"),
            (
                ##"<base href="https://um.example.org/"><base href="https://dois.example.org/"><meta property="og:image" content="a.png">"##,
                "https://um.example.org/a.png"
            ),
            (##"<base target="_blank"><meta property="og:image" content="a.png">"##, "https://example.com/blog/a.png"),
            (##"<base href=" "><meta property="og:image" content="a.png">"##, "https://example.com/blog/a.png"),
            (##"<base href="javascript:alert(1)"><meta property="og:image" content="a.png">"##, "https://example.com/blog/a.png"),
            (##"<base href="data:text/html,x"><meta property="og:image" content="a.png">"##, "https://example.com/blog/a.png"),
            (##"<base href="https://um.example.org/"><meta property="og:image" content="/abs.png">"##, "https://um.example.org/abs.png"),
        ])
    func baseVariants(inner: String, expected: String) throws {
        #expect(try parse(page(inner)).imageURL?.absoluteString == expected)
    }

    @Test(
        "Esquemas que não são http nem https são descartados, e a imagem seguinte na precedência assume",
        arguments: [
            "data:image/png;base64,iVBORw0KGgo=", "javascript:alert(1)", "ftp://example.com/a.png", "file:///Users/joao/a.png",
            "mailto:alguem@example.com", "blob:https://example.com/1234", "about:blank", "",
        ])
    func nonWebImagesAreDropped(reference: String) throws {
        let alone = try parse(page("<meta property=\"og:image\" content=\"\(reference)\">"))
        #expect(alone.imageURL == nil)

        let fallback = try parse(
            page(
                "<meta property=\"og:image:secure_url\" content=\"\(reference)\"><meta property=\"og:image\" content=\"\(reference)\"><meta name=\"twitter:image\" content=\"/ok.png\">"
            ))
        #expect(fallback.imageURL?.absoluteString == "https://example.com/ok.png")
    }

    @Test("Ícones que não são http nem https são descartados")
    func nonWebIconsAreDropped() throws {
        let metadata = try parse(
            page(
                ##"<link rel="icon" href="data:image/png;base64,AAAA"><link rel="icon" href="javascript:x"><link rel="icon" href="ftp://example.com/f.ico"><link rel="icon" href="/ok.png">"##
            ))
        #expect(metadata.iconURLs.map(\.absoluteString) == ["https://example.com/ok.png"])
    }

    // MARK: Ícones

    @Test("Ícones: apple-touch-icon, depois icon, depois shortcut icon; o maior sizes primeiro, sem sizes por último")
    func iconOrder() throws {
        let metadata = try parse(
            page(
                """
                <link rel="shortcut icon" href="/atalho.ico">
                <link rel="icon" href="/sem-tamanho.png">
                <link rel="icon" sizes="16x16" href="/i16.png">
                <link rel="apple-touch-icon" sizes="120x120" href="/a120.png">
                <link rel="icon" type="image/png" sizes="32x32" href="/i32.png">
                <link rel="apple-touch-icon-precomposed" sizes="180x180" href="/a180.png">
                <link rel="apple-touch-icon" href="/a-sem-tamanho.png">
                <link rel="icon" sizes="64x64" href="/i64.png">
                <link rel="shortcut icon" sizes="48x48" href="/atalho48.png">
                """
            ))
        #expect(
            metadata.iconURLs.map(\.path) == [
                "/a180.png", "/a120.png", "/a-sem-tamanho.png",
                "/i64.png", "/i32.png", "/i16.png", "/sem-tamanho.png",
                "/atalho48.png", "/atalho.ico",
            ])
    }

    @Test("Em empate de tamanho vale a ordem do documento")
    func iconTiesKeepDocumentOrder() throws {
        let metadata = try parse(
            page(
                ##"<link rel="icon" sizes="32x32" href="/b.png"><link rel="icon" sizes="32x32" href="/a.png"><link rel="icon" href="/z.png"><link rel="icon" href="/y.png">"##
            ))
        #expect(metadata.iconURLs.map(\.path) == ["/b.png", "/a.png", "/z.png", "/y.png"])
    }

    @Test(
        "O atributo rel é uma lista sem diferenciar maiúsculas; outros rel não são ícones",
        arguments: [
            (##"<link rel="ICON" href="/i.png">"##, ["/i.png"]),
            (##"<link rel="Shortcut Icon" href="/i.png">"##, ["/i.png"]),
            (##"<link rel="icon shortcut" href="/i.png">"##, ["/i.png"]),
            (##"<link rel="alternate icon" href="/i.png">"##, ["/i.png"]),
            (##"<link rel="APPLE-TOUCH-ICON" href="/i.png">"##, ["/i.png"]),
            (##"<link rel="stylesheet" href="/estilo.css"><link rel="preload" href="/f.woff2"><link rel="manifest" href="/m.json">"##, []),
            (##"<link rel="mask-icon" href="/mask.svg"><link rel="canonical" href="https://example.com/">"##, []),
            (##"<link href="/sem-rel.png">"##, []),
            (##"<link rel="icon">"##, []),
            (##"<link rel="icon" href="">"##, []),
        ])
    func relTokens(inner: String, expected: [String]) throws {
        #expect(try parse(page(inner)).iconURLs.map(\.path) == expected)
    }

    @Test(
        "sizes usa o maior lado da lista; any e valores inválidos contam como sem tamanho",
        arguments: [
            ("16x16 32x32 48x48", 48), ("32x32 16x16", 32), ("180X180", 180), ("48x24", 48), ("24x48", 48),
        ])
    func sizesParsing(sizes: String, side: Int) throws {
        let metadata = try parse(
            page(
                "<link rel=\"icon\" href=\"/sem.png\"><link rel=\"icon\" sizes=\"\(sizes)\" href=\"/com.png\"><link rel=\"icon\" sizes=\"\(side - 1)x\(side - 1)\" href=\"/menor.png\">"
            ))
        #expect(metadata.iconURLs.map(\.path) == ["/com.png", "/menor.png", "/sem.png"])
    }

    @Test("sizes = any ou inválido fica depois dos ícones com tamanho")
    func invalidSizesAreUnsized() throws {
        let metadata = try parse(
            page(
                ##"<link rel="icon" sizes="any" href="/any.svg"><link rel="icon" sizes="grande" href="/grande.png"><link rel="icon" sizes="0x0" href="/zero.png"><link rel="icon" sizes="16x16" href="/i16.png">"##
            ))
        #expect(metadata.iconURLs.map(\.path) == ["/i16.png", "/any.svg", "/grande.png", "/zero.png"])
    }

    @Test("Ícones repetidos aparecem uma vez, na posição do melhor grupo, e /favicon.ico não é acrescentado")
    func iconDeduplication() throws {
        let metadata = try parse(
            page(
                ##"<link rel="icon" href="/mesmo.png"><link rel="apple-touch-icon" href="https://example.com/mesmo.png"><link rel="icon" href="/outro.png"><link rel="icon" href="/outro.png">"##
            ))
        #expect(metadata.iconURLs.map(\.path) == ["/mesmo.png", "/outro.png"])
        #expect(try parse(page("<title>Sem ícones</title>")).iconURLs.isEmpty)
    }

    // MARK: Onde a leitura para

    @Test("Metadados depois de </head> ou dentro do <body> são ignorados")
    func stopsAtEndOfHead() throws {
        let afterHead = try parse(
            ##"<html><head><title>Do head</title></head><meta property="og:title" content="Tarde demais"><link rel="icon" href="/tarde.png"><body></body></html>"##
        )
        #expect(afterHead.title == "Do head")
        #expect(afterHead.iconURLs.isEmpty)

        let inBody = try parse(
            ##"<html><head><title>Do head</title></head><body><meta property="og:site_name" content="No body"><link rel="icon" href="/body.png"></body></html>"##
        )
        #expect(inBody.siteName == nil)
        #expect(inBody.iconURLs.isEmpty)
    }

    @Test("Sem </head>, a leitura para no primeiro <body, em qualquer caixa")
    func stopsAtBody() throws {
        for body in ["<body>", "<BODY class=\"x\">", "<Body\n>", "<body"] {
            let metadata = try parse(
                ##"<html><head><meta property="og:title" content="Antes"><title>T</title>"## + body
                    + ##"<meta property="og:site_name" content="Depois">"##)
            #expect(metadata.title == "Antes")
            #expect(metadata.siteName == nil)
        }
        for end in ["</head>", "</HEAD>", "</Head >", "</head\n>"] {
            let metadata = try parse(
                ##"<head><meta property="og:title" content="Antes">"## + end + ##"<meta property="og:site_name" content="Depois">"##)
            #expect(metadata.title == "Antes")
            #expect(metadata.siteName == nil)
        }
    }

    @Test("Documento sem <head> é lido do começo até o <body")
    func documentWithoutHead() throws {
        let metadata = try parse(
            ##"<!DOCTYPE html><meta charset="utf-8"><title>Sem head</title><meta property="og:site_name" content="Site"><link rel="icon" href="/i.png"><p>texto</p><body><meta property="og:title" content="No body">"##
        )
        #expect(metadata.title == "Sem head")
        #expect(metadata.siteName == "Site")
        #expect(metadata.iconURLs.map(\.path) == ["/i.png"])

        // Sem <head> nem <body>, o documento inteiro é lido.
        #expect(try parse(##"<meta property="og:title" content="Só meta">"##).title == "Só meta")
        // Começar pelo <body> não deixa nada para ler.
        #expect(try parse(##"<body><meta property="og:title" content="Nada">"##).title == nil)
    }

    @Test("<header> e outras tags que começam com head ou body não encerram a leitura")
    func similarTagNames() throws {
        let metadata = try parse(
            ##"<header>Topo</header><headline></headline><bodyguard></bodyguard><meta property="og:title" content="Ainda no head"><body>"##)
        #expect(metadata.title == "Ainda no head")
    }

    @Test("Comentários e o texto de <script> e <style> não são lidos como tags")
    func commentsAndRawText() throws {
        let metadata = try parse(
            page(
                """
                <!-- <meta property="og:title" content="Comentado"> </head> <body> -->
                <!--[if lt IE 9]><link rel="icon" href="/ie.png"><![endif]-->
                <script>var t = '<meta property="og:site_name" content="Script">'; document.write("</head><body>");</script>
                <style>/* <link rel="icon" href="/css.png"> */</style>
                <script type="application/ld+json">{"x": "<title>JSON</title>"}</script>
                <meta property="og:title" content="Real">
                <link rel="icon" href="/real.png">
                """
            ))
        #expect(metadata.title == "Real")
        #expect(metadata.siteName == nil)
        #expect(metadata.iconURLs.map(\.path) == ["/real.png"])
    }

    @Test("Comentários vazios e abruptos fecham como nos navegadores")
    func shortComments() throws {
        for comment in ["<!-->", "<!--->", "<!---->", "<!-- -->"] {
            let metadata = try parse(page(comment + ##"<meta property="og:title" content="Depois">"##))
            #expect(metadata.title == "Depois", "\(comment)")
        }
        // <!DOCTYPE>, CDATA e instruções são pulados.
        let metadata = try parse(##"<?xml version="1.0"?><!DOCTYPE html><![CDATA[ x ]]><meta property="og:title" content="Depois">"##)
        #expect(metadata.title == "Depois")
    }

    // MARK: Codificação

    private let cafe: [UInt8] = Array("Caf".utf8) + [0xE9]  // "Café" em ISO-8859-1
    private let cafeUTF8: [UInt8] = Array("Café".utf8)

    private func titleDocument(_ title: [UInt8], head: String = "") -> [[UInt8]] {
        [Array("<html><head>\(head)<title>".utf8), title, Array("</title></head><body></body></html>".utf8)]
    }

    @Test(
        "Latin-1 declarado em <meta charset> ou em <meta http-equiv> é decodificado",
        arguments: [
            ##"<meta charset="iso-8859-1">"##,
            ##"<meta charset=ISO-8859-1>"##,
            ##"<meta charset=" iso-8859-1 ">"##,
            ##"<meta charset='latin1'>"##,
            ##"<META CHARSET="Windows-1252">"##,
            ##"<meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">"##,
            ##"<meta http-equiv="content-type" content="text/html;charset=iso-8859-1">"##,
            ##"<meta http-equiv=Content-Type content="text/html; charset = 'iso-8859-1'">"##,
        ])
    func latin1FromMeta(head: String) throws {
        #expect(try parse(bytes(titleDocument(cafe, head: head))).title == "Café")
    }

    @Test(
        "Latin-1 informado pelo cabeçalho HTTP é decodificado, sem <meta>",
        arguments: ["iso-8859-1", "ISO-8859-1", "latin1", "windows-1252"])
    func latin1FromHeader(name: String) throws {
        #expect(try parse(bytes(titleDocument(cafe)), encoding: name).title == "Café")
    }

    @Test("O cabeçalho HTTP vale mais que o <meta>, e o <meta> vale quando não há cabeçalho")
    func headerBeatsMeta() throws {
        let latin1Meta = ##"<meta charset="iso-8859-1">"##
        let utf8Meta = ##"<meta charset="utf-8">"##
        // Bytes UTF-8 com <meta> dizendo Latin-1: o cabeçalho utf-8 manda.
        #expect(try parse(bytes(titleDocument(cafeUTF8, head: latin1Meta)), encoding: "utf-8").title == "Café")
        // Bytes Latin-1 com <meta> dizendo UTF-8: o cabeçalho iso-8859-1 manda.
        #expect(try parse(bytes(titleDocument(cafe, head: utf8Meta)), encoding: "iso-8859-1").title == "Café")
        // Sem cabeçalho, o <meta> decide.
        #expect(try parse(bytes(titleDocument(cafeUTF8, head: utf8Meta))).title == "Café")
        #expect(try parse(bytes(titleDocument(cafe, head: latin1Meta))).title == "Café")
    }

    @Test("Sem declaração: UTF-8 se for válido, Latin-1 como último recurso")
    func undeclaredEncoding() throws {
        #expect(try parse(bytes(titleDocument(cafeUTF8))).title == "Café")
        #expect(try parse(bytes(titleDocument(cafe))).title == "Café")
        #expect(try parse(bytes(titleDocument(Array("Ação".utf8)))).title == "Ação")
        // Nome de codificação desconhecido é como não declarar.
        #expect(try parse(bytes(titleDocument(cafeUTF8)), encoding: "x-nao-existe").title == "Café")
        #expect(try parse(bytes(titleDocument(cafe, head: ##"<meta charset="klingon">"##))).title == "Café")
    }

    @Test("UTF-8 declarado resiste a bytes inválidos soltos")
    func declaredUTF8ToleratesStrayBytes() throws {
        let document = bytes([
            Array(##"<head><meta charset="utf-8"><title>"##.utf8), cafeUTF8, Array("</title></head><body>".utf8), [0xFF, 0xFE, 0x80],
        ])
        #expect(try parse(document).title == "Café")
        #expect(
            try parse(bytes([Array("<title>".utf8), cafeUTF8, Array("</title>".utf8), [0xFF, 0xFE]]), encoding: "UTF-8").title == "Café")
    }

    @Test("Declarado como iso-8859-1, os bytes 0x80 a 0x9F são aspas e travessões do windows-1252")
    func latin1HeaderMeansWindows1252() throws {
        let title: [UInt8] = [0x93] + Array("oi".utf8) + [0x94, 0x20, 0x96, 0x20, 0x80]
        #expect(try parse(bytes(titleDocument(title)), encoding: "iso-8859-1").title == "“oi” – €")
    }

    @Test("O <meta> de codificação só vale nos primeiros 4 KB")
    func metaCharsetBeyondFourKilobytesIsIgnored() throws {
        let padding = "<!-- \(String(repeating: "x", count: 5_000)) -->"
        let late = bytes(titleDocument(cafeUTF8, head: padding + ##"<meta charset="iso-8859-1">"##))
        // Se o <meta> tardio valesse, os bytes UTF-8 virariam "CafÃ©".
        #expect(try parse(late).title == "Café")
        let early = bytes(titleDocument(cafe, head: ##"<meta charset="iso-8859-1">"## + padding))
        #expect(try parse(early).title == "Café")
    }

    @Test("UTF-8 com marca de ordem de bytes e UTF-16 declarado no cabeçalho")
    func byteOrderMarks() throws {
        let withBOM = bytes([[0xEF, 0xBB, 0xBF], Array(##"<head><meta property="og:title" content="Com BOM"></head>"##.utf8)])
        #expect(try parse(withBOM).title == "Com BOM")

        let utf16 = try #require("<head><title>Olá</title></head>".data(using: .utf16))
        #expect(try parse(utf16, encoding: "utf-16").title == "Olá")

        // Um <meta> lido como ASCII não pode estar em UTF-16: vale UTF-8.
        let liar = bytes(titleDocument(cafeUTF8, head: ##"<meta charset="utf-16">"##))
        #expect(try parse(liar).title == "Café")
    }

    @Test("O corte nos 512 KB no meio de um caractere UTF-8 não faz a página virar Latin-1")
    func truncationInsideACharacterKeepsUTF8() throws {
        let limit = 512 * 1024
        var document = Array("<html><head><title>Café ção</title></head><body>".utf8)
        document += [UInt8](repeating: UInt8(ascii: "x"), count: limit - 1 - document.count)
        document += Array("é".utf8) + Array("fim".utf8)  // o primeiro byte de "é" é o último dos 512 KB
        #expect(document.count > limit && document[limit - 1] == 0xC3)
        #expect(try parse(Data(document)).title == "Café ção")
    }

    // MARK: Texto

    @Test("Espaços, quebras e espaço sem quebra viram um espaço só, e as pontas são aparadas")
    func whitespaceIsCollapsed() throws {
        let metadata = try parse(
            page(
                "<meta property=\"og:title\" content=\"  Um \t\n dois&nbsp;&nbsp;três\r\n quatro  \">"
                    + "<meta name=\"description\" content=\"\n\n  Linha 1\n\n\nLinha 2\t\tLinha 3 \u{00A0} \">"
                    + "<meta property=\"og:site_name\" content=\"  Meu   Site  \">"
            ))
        #expect(metadata.title == "Um dois três quatro")
        #expect(metadata.summary == "Linha 1 Linha 2 Linha 3")
        #expect(metadata.siteName == "Meu Site")
    }

    @Test(
        "Texto vazio, só com espaços ou só com espaços sem quebra vira nil",
        arguments: ["", "   ", "\n\t\n", "&nbsp;", "&#32;&#160;", "\u{00A0}"])
    func blankTextIsNil(raw: String) throws {
        let metadata = try parse(
            page(
                "<title>\(raw)</title><meta name=\"description\" content=\"\(raw)\"><meta property=\"og:site_name\" content=\"\(raw)\">"
            ))
        #expect(metadata.title == nil && metadata.summary == nil && metadata.siteName == nil)
    }

    @Test("Resumo de até 300 caracteres fica intacto")
    func shortSummaryIsUntouched() throws {
        let exact = String(repeating: "abcdefghi ", count: 29) + "abcdefghij"  // 290 + 10 = 300
        #expect(exact.count == 300)
        #expect(try parse(page("<meta name=\"description\" content=\"\(exact)\">")).summary == exact)
    }

    @Test("Resumo maior que 300 é cortado em fronteira de palavra e termina com a reticência, dentro dos 300 caracteres")
    func longSummaryIsCutAtAWordBoundary() throws {
        let words = (1...200).map { "palavra\($0)" }
        let long = words.joined(separator: " ")
        #expect(long.count > 300)
        let summary = try #require(try parse(page("<meta name=\"description\" content=\"\(long)\">")).summary)

        #expect(summary.count <= 300)
        #expect(summary.hasSuffix("…"))
        let kept = String(summary.dropLast())
        #expect(!kept.hasSuffix(" "))
        // Só palavras inteiras, na ordem original.
        #expect(long.hasPrefix(kept))
        #expect(words.contains(String(kept.split(separator: " ").last ?? "")))
        // E nenhuma palavra a mais teria cabido: a seguinte estouraria os 299 caracteres antes da reticência.
        let nextWord = try #require(long.dropFirst(kept.count + 1).split(separator: " ").first)
        #expect(kept.count + 1 + nextWord.count > 299)
    }

    @Test("Resumo sem nenhum espaço é cortado no limite")
    func summaryWithoutSpacesIsCutHard() throws {
        let long = String(repeating: "a", count: 500)
        let summary = try #require(try parse(page("<meta name=\"description\" content=\"\(long)\">")).summary)
        #expect(summary == String(repeating: "a", count: 299) + "…")
    }

    @Test("O corte conta o texto já sem entidades e com espaços colapsados")
    func summaryLimitCountsNormalizedText() throws {
        let padded = String(repeating: "a&amp;b    ", count: 70)  // 770 caracteres brutos, 279 depois de decodificar e colapsar
        let expected = Array(repeating: "a&b", count: 70).joined(separator: " ")
        #expect(expected.count == 279)
        let summary = try #require(try parse(page("<meta name=\"description\" content=\"\(padded)\">")).summary)
        #expect(summary == expected)
    }

    @Test("Título e nome do site também respeitam o limite de 300 caracteres")
    func titleIsLimitedToo() throws {
        let long = (1...100).map { "titulo\($0)" }.joined(separator: " ")
        let title = try #require(try parse(page("<title>\(long)</title>")).title)
        #expect(title.count <= 300 && title.hasSuffix("…"))
    }

    // MARK: Robustez

    @Test("Entrada vazia ou sem nada de útil devolve tudo vazio")
    func emptyInput() throws {
        let empty = HTMLHeadMetadata()
        #expect(try parse(Data()) == empty)
        #expect(try parse("") == empty)
        #expect(try parse("   \n\t ") == empty)
        #expect(try parse("<html><head></head><body></body></html>") == empty)
        #expect(try parse("só texto, sem tag nenhuma") == empty)
    }

    @Test("Lixo binário não trava nem inventa metadados")
    func binaryGarbage() throws {
        var generator = SplitMix64(seed: 42)
        let garbage = Data((0..<200_000).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
        #expect(try parse(garbage) == HTMLHeadMetadata())
        #expect(try parse(garbage, encoding: "iso-8859-1") == HTMLHeadMetadata())
        #expect(try parse(Data((0...255).map { UInt8($0) })) == HTMLHeadMetadata())
        #expect(try parse(Data(repeating: 0, count: 10_000)) == HTMLHeadMetadata())
    }

    @Test(
        "HTML malformado ou cortado no meio não trava",
        arguments: [
            "<", "<<<<", "<meta", "<meta ", "<meta property", "<meta property=", "<meta property=\"og:title",
            "<meta property=\"og:title\" content=\"abc",
            "<meta property='og:title' content='abc", "<title>", "<title>sem fim", "<!--",
            "<!-- sem fim <meta property=\"og:title\" content=\"x\">",
            "<script>sem fim <meta property=\"og:title\" content=\"x\">", "</", "</head", "<!", "<?", "<!DOCTYPE", "&", "&#", "&#x", "=",
            "\"'\"'",
            "<meta =>", "<meta ==== >", "<link rel=icon href=>", "<a b='c' d=\"e\" f=g h", "<>",
            "< meta property=\"og:title\" content=\"x\">",
        ])
    func malformedInputDoesNotHang(html: String) throws {
        // O que importa aqui é terminar sem falhar; o conteúdo útil quase nunca existe nesses casos.
        let metadata = try parse(html)
        #expect(metadata.iconURLs.count < 2)
    }

    @Test("Metadados além dos primeiros 512 KB são ignorados")
    func onlyTheFirstHalfMegabyteIsRead() throws {
        let padding = "<!-- \(String(repeating: "x", count: 520 * 1024)) -->"
        let metadata = try parse(
            ##"<head><meta property="og:title" content="Cedo">"## + padding + ##"<meta property="og:site_name" content="Tarde"></head>"##)
        #expect(metadata.title == "Cedo")
        #expect(metadata.siteName == nil)
    }

    @Test("Entradas patológicas de 500 KB terminam em segundos, sem custo quadrático")
    func pathologicalInputsStayLinear() throws {
        let size = 500 * 1024
        let inputs = [
            String(repeating: "<title>", count: size / 7),
            String(repeating: "<!-", count: size / 3),
            String(repeating: "<a b='", count: size / 6),
            String(repeating: "<script>", count: size / 8),
            String(repeating: "&#", count: size / 2),
            String(repeating: "<meta content=\"", count: size / 15),
            "<title>" + String(repeating: "&amp;", count: size / 5) + "</title>",
            String(repeating: "<", count: size),
        ]
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for input in inputs { _ = try parse(input) }
        }
        #expect(elapsed < .seconds(10), "levou \(elapsed)")
    }

    @Test("Mutações aleatórias de uma página válida nunca falham")
    func randomMutationsNeverCrash() throws {
        let seed = Array(
            """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>T &amp; U</title><base href="/x/"><meta property="og:title" content="A">
            <link rel="icon" sizes="16x16 32x32" href="a.png"><script>var a = "</scr" + "ipt>";</script><!-- c --></head><body></body></html>
            """.utf8)
        var generator = SplitMix64(seed: 7)
        for _ in 0..<500 {
            var mutated = seed
            for _ in 0..<Int(generator.next() % 12 + 1) {
                let position = Int(generator.next() % UInt64(mutated.count))
                switch generator.next() % 3 {
                case 0: mutated[position] = UInt8(truncatingIfNeeded: generator.next())
                case 1: mutated.remove(at: position)
                default: mutated.insert(contentsOf: Array("<>\"'=/&;-!".utf8).shuffled(using: &generator), at: position)
                }
            }
            _ = try parse(Data(mutated), encoding: generator.next() % 2 == 0 ? nil : "iso-8859-1")
        }
    }
}

/// Gerador pseudoaleatório com semente fixa: os testes repetem sempre a mesma sequência.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
