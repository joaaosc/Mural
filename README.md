# Mural

App de macOS 27 em SwiftUI para reunir referências visuais num mural: imagens, vídeos,
PDFs, notas, post-its e listas. O conteúdo entra colando (⌘V), arrastando para a janela
ou por Arquivo › Importar…, e fica salvo entre aberturas.

A interface tem três níveis, cada um crescendo a partir do cartão clicado:

1. **Mural**: cartões livres, com zoom, filtros e prévia de pastas ao passar o ponteiro.
2. **Pasta**: o conteúdo em colunas de alturas livres, com etiquetas nos cantos.
3. **Item**: detalhe por tipo (imagem com paleta e metadados, vídeo, PDF, texto, lista).

Controles flutuantes usam o material Liquid Glass padrão do sistema.

## Requisitos

- macOS 27 e Xcode 27.2 ou mais novo (o projeto usa o formato JSON `project.xcproj`).

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `Packages/MuralKit` | Domínio sem interface: modelos, importação, gravação, paleta, estado observável. |
| `Mural/` | App: telas organizadas por área (`Board`, `Collection`, `Detail`, `Cards`, `Chrome`, `Navigation`, `Input`, `Media`, `Style`). |
| `MuralTests/` | Testes do app com Swift Testing. |
| `MuralUITests/` | Testes de interface que abrem o app com um mural de teste isolado. |
| `Config/Project.xcconfig` | Configurações de build comuns a todos os alvos. |
| `scripts/` | Verificação completa e conferência do arquivo de projeto. |

Os dados ficam em `~/Library/Containers/com.joaocosta.Mural/Data/Library/Application Support/Mural`:
`board.json` com o mural e `Items/` com as cópias dos arquivos colados.

## Comandos

```sh
scripts/verify.sh          # formatação, projeto, domínio, build e testes do app
UI=1 scripts/verify.sh     # inclui os testes de interface (exigem o modo de automação)
swift test --package-path Packages/MuralKit
xcodebuild -project Mural.xcodeproj -scheme Mural -destination 'platform=macOS' build
swift format -i -r Mural MuralTests MuralUITests Packages/MuralKit/Sources Packages/MuralKit/Tests
```

## Convenções

- Regras de negócio ficam em `MuralKit`, com testes; o app só monta telas e liga ao sistema.
- O arquivo de projeto muda só por `xcrun xcodeproj`, nunca à mão. Arquivos novos de código
  entram sozinhos, porque as pastas do app são sincronizadas com o disco.
- `scripts/verify.sh` passa antes de cada commit.
- Commits pequenos e coesos, mensagem em português com até três linhas, descrevendo a mudança.
- Nenhum arquivo de mídia de teste é versionado; os testes geram as imagens de que precisam.
