# Mural

App de macOS 27 em SwiftUI para reunir referências visuais num mural: imagens, vídeos,
PDFs, notas, post-its, listas e links. O conteúdo entra colando (⌘V), arrastando para a janela,
pela barra de criação no centro inferior ou por Arquivo › Importar…, e fica salvo entre aberturas.

A interface tem três níveis, cada um crescendo a partir do cartão clicado:

1. **Mural**: cartões livres, com zoom, filtros e prévia de pastas ao passar o ponteiro.
2. **Pasta**: o conteúdo em colunas de alturas livres, com etiquetas nos cantos.
3. **Item**: detalhe por tipo (imagem com paleta e metadados, vídeo, PDF, texto, lista, página do link).

Controles flutuantes usam o material Liquid Glass padrão do sistema.

## Abas e murais

- **Uma janela, com abas como as do Safari** (layout compacto): cada mural aberto é uma aba na
  mesma linha dos botões da janela. Um mural fica em uma aba só; abri-lo de novo leva à aba dele.
  Trocar de aba não relê o disco, e o mural volta ao mesmo ponto.
- **Barra lateral** (botão ao lado dos botões da janela, ⌃⌘S): todos os murais; clicar abre a aba.
  **+** e ⌘N criam um mural novo numa aba. Com ela aberta, as abas começam depois dela, num vidro
  só em volta delas; a barra lateral é mais encorpada que o mural, que deixa ver o fundo como vidro.
- ⌘W fecha a aba; fechar a última fecha a janela, e o app continua aberto. Visualizar › Mostrar
  Todos os Murais (⇧⌘\) ou o Dock reabrem a janela. ⌃⇥ e ⌃⇧⇥ passam de uma aba para outra.
- As abas abertas voltam junto com a janela quando o macOS reabre as janelas do app.
- **Excluir mural**: botão direito no mural da barra lateral ou na aba, ou Arquivo › Excluir Mural….
  Depois da confirmação, a aba fecha e o mural vai para o Lixo do Mac; o rascunho de exemplo é
  descartado.

## Cores

- **Cor no menu do botão direito**, como as tags do Finder: vermelho, laranja, amarelo, verde, azul,
  roxo e cinza, uma por cartão. Tocar de novo na cor (ou em "Remover cor") tira a cor.
- **Vários de uma vez**: com cartões marcados (⌘-clique ou Shift + arrastar), as bolinhas da barra do
  seletor pintam todos (ou tiram a cor).
- **Filtro por cor**: o botão de cor na barra de filtros destaca uma cor e esmaece o resto, junto
  com o filtro de tipo; cada nível começa sem filtro.
- Pasta, nota e lista ficam tingidas de leve (a pasta também ganha a aba na cor cheia, e a página
  dela, um tom mais leve); post-it, foto, vídeo, PDF e link ganham uma bolinha no canto.
- Um mural com alguma cor usa a versão 4 do formato: builds anteriores se recusam a abri-lo em vez
  de perder as cores ao gravar.

## Texto

- **Card de texto**: título num campo próprio e corpo em Markdown (títulos, listas, tarefas,
  citações, código, **negrito**). Editar e Concluir ficam na pílula da página (⌘E, ⌘↩);
  ⌘B e ⌘I, no menu Formatar. As tarefas (`- [ ]`) marcam e desmarcam com um clique na página
  da nota, sem mudar as frases curtas nem fechar os parágrafos abertos.
- **Sticker** (post-it): texto curto sobre papel colorido, com as cinco cores na edição.
- **Leitura dobrável**: no corpo das notas e no texto de abertura das listas, cada parágrafo
  de duas frases ou mais mostra só uma frase até ser clicado, e abre no lugar
  ([StretchText](../Workbench/StretchText)). A miniatura do card mostra só as frases curtas.
  Stickers não dobram.
- **Frase curta**: escolhida em segundo plano pelo modelo do aparelho (Apple Intelligence),
  entre as frases que já existem, e guardada na nota até o texto mudar. Sem o modelo,
  vale a primeira frase, com um aviso discreto no fim da nota. Os parágrafos abertos
  voltam abertos ao reabrir a nota.
- **⌘V com texto solto** abre um popup que pergunta se ele vira sticker, card de texto
  ou, quando parece lista, lista; a sugestão fica no Return.
- **Imagem no card de texto**: editando o corpo, ⌘V, Editar › Colar ou soltar uma imagem a põem
  numa linha própria do Markdown, `![Imagem colada](arquivo)`, onde está o cursor (com ⌘V no título
  ou fora do texto, ela vai para o fim do corpo; com a página aberta sem editar, ⌘V acrescenta no
  fim). Vale arquivo de imagem, captura de tela, "Copiar Imagem" e texto formatado com imagens
  (Notas, TextEdit, Pages, Safari); imagem que só existe na internet não é baixada. A leitura e a
  miniatura mostram a imagem; o arquivo fica em `Items/` e sai do disco quando nenhuma nota o cita
  mais. Murais com imagem em nota usam a versão 5 do formato.
- **Salvar no Notas**, na pílula da página e no menu do cartão (nota, sticker e lista): abre o
  painel do próprio Notas já preenchido, com títulos, listas, tarefas e imagens. Cada vez cria uma
  nota nova; o Mural não lê nem atualiza notas do Notas.

## Marcar vários cartões

- **⌘-clique** marca ou desmarca um cartão; segurar ⌘ mostra o círculo de marcar em todos.
- **Shift + arrastar** numa área vazia, no mural ou dentro de uma pasta, desenha um retângulo: os
  cartões que ele cruza somam-se aos já marcados. Começado em cima de um cartão, o arrasto move o cartão.
- A barra do seletor mostra quantos estão marcados, as cores, Apagar (⌫, com confirmação) e Cancelar
  (Esc).

## Pastas

- **Pasta dentro de pasta**, até 8 níveis: "Pasta" na barra de criação e Arquivo › Nova pasta…
  (⌃⌘N) criam a subpasta na pasta aberta. No mural, soltar uma pasta sobre outra a guarda dentro
  (só destacam as pastas que podem recebê-la).
- **Renomear…** no menu do botão direito da pasta (no mural ou dentro de outra pasta) abre uma folha
  com o nome atual.
- O menu do botão direito tem "Mover para a pasta ▸" com o caminho ("Viagem › Hotel"), "Mover para
  a pasta de cima" e "Mover para o mural". Apagar uma pasta apaga tudo que há dentro, em todos os
  níveis, com o total no aviso.
- A pasta mostra em leque, pela borda direita, os três cartões mais recentes de dentro.
- Murais com pasta dentro de pasta usam a versão 2 do formato.

## Lembretes

- **Lembretes…**, na barra de criação e no menu Arquivo, abre uma folha com as listas e os lembretes
  do app Lembretes; cada lembrete escolhido vira um cartão com a bolinha na cor da lista, a data
  (em vermelho se atrasado), a prioridade e a lista. Na primeira vez o macOS pede acesso.
- Clicar na bolinha marca ou desmarca o lembrete no próprio app Lembretes; a página tem Marcar como
  concluído e Abrir no Lembretes. Os cartões se atualizam ao abrir o mural, ao voltar ao app e quando
  o Lembretes muda; um lembrete apagado lá fica acinzentado, e sem acesso o cartão mostra o último
  estado guardado. Apagar o cartão não apaga o lembrete.
- Murais com lembretes usam a versão 6 do formato.

## Links

- **⌘V com um endereço** cria um cartão de link com imagem, ícone, site, título e resumo da
  página. Vale para Copiar Link, o endereço da barra e favoritos ou itens da Lista de Leitura
  copiados no Safari, que já trazem título, resumo e imagem; vários endereços, um por linha,
  viram um cartão cada.
- **Página no detalhe**: abrir o cartão mostra a página dentro do Mural, com página anterior e
  próxima, Abrir no navegador, Copiar link e Usar como prévia (o trecho visível vira a imagem
  do cartão). Só `http` e `https` abrem dentro; e-mail, telefone, mensagem e FaceTime vão para
  o app do sistema.
- **Prévias**: buscadas pela rede quando o cartão aparece, com limite por site; ficam em
  `LinkPreviews/`, ao lado dos murais, e se refazem sozinhas se o arquivo sumir. "Atualizar
  prévia", no menu do cartão, busca de novo.

## Requisitos

- macOS 27 e Xcode 27.2 ou mais novo (o projeto usa o formato JSON `project.xcproj`).
- O pacote [StretchText](../Workbench/StretchText) em `../Workbench/StretchText`, ao lado
  desta pasta: o projeto e o `MuralKit` apontam para ele por caminho relativo. A imagem dentro
  da nota e a tarefa clicável precisam da `main` do Workbench a partir de `d67fd91` (bloco de
  imagem e `togglingTask`/`stretchMarkdownTaskToggle`).
- Para a escolha das frases pelo modelo: um Mac com Apple Intelligence ligada. Sem ela,
  o app funciona com a primeira frase.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `Packages/MuralKit` | Domínio sem interface: modelos, importação, gravação, paleta, estado observável. |
| `Mural/` | App: telas organizadas por área (`Tabs`, `Board`, `Collection`, `Detail`, `Cards`, `Chrome`, `Navigation`, `Input`, `Media`, `Style`). |
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
scripts/ui-tests.sh        # só os de interface; esperam o Mac ficar livre de outros testes
swift test --package-path Packages/MuralKit
MURAL_RUNTIME_TESTS=1 swift test --package-path Packages/MuralKit --filter KeySentenceRuntimeTests  # modelo real
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
- Nos testes (e com `-disableOnDeviceModel`), o modelo do aparelho fica desligado: a frase
  curta é sempre a primeira, para nada mudar sozinho no meio de uma verificação.
