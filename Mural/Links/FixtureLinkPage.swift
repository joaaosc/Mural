import Foundation

/// Página local de exemplo, sem rede: é o que o detalhe do link mostra nos testes de interface e nas prévias do Xcode.
enum FixtureLinkPage {
    /// Título da página e texto do cabeçalho: os testes de interface procuram por ele no conteúdo web.
    static let title = "Página de exemplo"

    static let html = """
        <!doctype html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          :root { color-scheme: light dark; }
          body { font: 17px/1.55 -apple-system, system-ui, sans-serif; max-width: 640px; margin: 0 auto; padding: 72px 28px 160px; }
          h1 { font-size: 36px; line-height: 1.15; margin: 0 0 12px; }
          .lead { font-size: 20px; color: GrayText; margin: 0 0 40px; }
          h2 { font-size: 22px; margin: 36px 0 8px; }
        </style>
        </head>
        <body>
        <h1>\(title)</h1>
        <p class="lead">Conteúdo local do Mural, usado nos testes e nas prévias, sem acesso à rede.</p>
        <h2>Primeira seção</h2>
        <p>Um parágrafo de exemplo para a página ter o que rolar e o que mostrar na imagem de prévia do cartão.</p>
        <h2>Segunda seção</h2>
        <p>Outro parágrafo de exemplo. A página é só texto: nada é buscado fora do app.</p>
        <h2>Terceira seção</h2>
        <p>Mais um parágrafo, para a rolagem passar da primeira tela.</p>
        </body>
        </html>
        """
}
