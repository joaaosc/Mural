# Mural

App de macOS 27 em SwiftUI para reunir referências visuais num mural: imagens, vídeos,
PDFs, notas, post-its, listas e links. O conteúdo entra colando (⌘V), arrastando para a janela,
pela barra de criação no centro inferior ou por Arquivo › Importar…, e fica salvo entre aberturas.

A interface tem três níveis, cada um crescendo a partir do cartão clicado:

1. **Mural**: cartões livres, com zoom, filtros e prévia de pastas ao passar o ponteiro.
2. **Pasta**: o conteúdo em colunas de alturas livres, com etiquetas nos cantos; os post-its podem ser
   arrastados para qualquer lugar dela, por cima das colunas.
3. **Item**: detalhe por tipo (imagem com paleta e metadados, vídeo, PDF, texto, lista, página do link).

Controles flutuantes usam o material Liquid Glass padrão do sistema.

## Abas e murais

- **Uma janela, com abas como as do Safari** (layout compacto): cada mural aberto é uma aba na
  mesma linha dos botões da janela. Um mural fica em uma aba só; abri-lo de novo leva à aba dele.
  Trocar de aba não relê o disco, e o mural volta ao mesmo ponto.
- **Barra lateral** (botão ao lado dos botões da janela, ⌃⌘S): todos os murais, cada um com a capa em
  miniatura, quando foi atualizado e um selo quando está no iCloud ou foi compartilhado; clicar abre a aba.
  Os murais abertos nesta janela vêm primeiro; com mais de cinco, os cinco mais recentes ganham a seção
  "Recentes" e o resto fica em ordem alfabética. O campo de busca no alto filtra pelo nome. **+** (no alto e
  no rodapé) e ⌘N criam um mural novo numa aba; o rodapé mostra a contagem ("12 murais · 3 no iCloud").
  Com ela aberta, as abas começam depois dela, num vidro só em volta delas; a barra lateral é mais
  encorpada que o mural, que deixa ver o fundo como vidro.
- ⌘W fecha a aba; fechar a última fecha a janela, e o app continua aberto. Visualizar › Mostrar
  Todos os Murais (⇧⌘\) ou o Dock reabrem a janela. ⌃⇥ e ⌃⇧⇥ passam de uma aba para outra.
- As abas abertas voltam junto com a janela quando o macOS reabre as janelas do app.
- **Excluir mural**: botão direito no mural da barra lateral ou na aba, ou Arquivo › Excluir Mural….
  Depois da confirmação, a aba fecha e o mural vai para o Lixo do Mac; o rascunho de exemplo é
  descartado.

## Cores

- **Tema em Ajustes › Geral › Aparência**: Neutro (os cinzas de sempre), Quente (areia e linho), Frio
  (azul-gelo) ou Verde (sálvia). O tema muda o fundo do mural (com um gradiente leve), das páginas e o papel
  dos cartões, com variante clara, escura e de alto contraste; claro e escuro continuam seguindo o sistema.
  Post-its e as cores das tags não mudam. As capas já desenhadas só acompanham o tema quando o mural muda.
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
- **Vídeo ao passar o ponteiro**: com o ponteiro parado meio segundo sobre um cartão de vídeo, ele toca
  mudo e em laço dentro do cartão; ao sair, volta à miniatura. Vale no mural e dentro da pasta; não vale com
  o seletor de ⌘ aberto, na prévia de pasta nem com Reduzir Movimento. Live Photo ainda não: o Fotos entrega
  só a imagem, sem o vídeo que a acompanha.

## Texto

- **Card de texto**: título num campo próprio e corpo em Markdown (títulos, listas, tarefas,
  citações, código, **negrito**). Editar e Concluir ficam na pílula da página (⌘E, ⌘↩);
  ⌘B e ⌘I, no menu Formatar. As tarefas (`- [ ]`) marcam e desmarcam com um clique na página
  da nota, sem mudar as frases curtas nem fechar os parágrafos abertos.
- **Sticker** (post-it): texto curto sobre papel colorido, com as cinco cores na edição.
- **Mudar o tamanho** de um sticker ou de um texto livre solto no mural: arrastar o canto inferior
  direito (a alça aparece com o ponteiro em cima; Shift mantém a proporção) ou o menu do botão
  direito › Tamanho (Pequeno, Médio, Grande, Muito grande ou o padrão). A letra cresce junto. Dentro
  de uma pasta o sticker volta ao tamanho das colunas e guarda o dele para quando sair. Murais com
  algum tamanho escolhido usam a versão 11 do formato.
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
- **Post-it solto na pasta**: arrastar um post-it dentro da pasta o deixa solto onde foi largado, por cima
  das colunas, e o lugar fica guardado. Solto sobre uma subpasta (que fica destacada antes de soltar), ele
  entra nela. Levado para outra pasta ou para o mural, ele volta às colunas. Só post-its se movem assim.
  O post-it novo criado na pasta já nasce solto, no meio do que está à vista. Murais com post-it solto
  numa pasta usam a versão 9 do formato.

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

## Apple Music

- **Arrastar do app Música** um álbum, uma faixa, uma playlist (do catálogo ou sua) ou uma estação
  cria um cartão com capa, tipo, título e artista, no ponto onde foi solto. ⌘C de faixas no Música
  e ⌘V no mural, ou um link `music.apple.com` copiado (Compartilhar › Copiar Link), fazem o mesmo.
  A capa vem no próprio arrasto ou é baixada e guardada em `LinkPreviews/`.
- **Tocar**: o botão sobre a capa (aparece com o ponteiro em cima), o menu do cartão ou a página
  tocam pelo Apple Music dentro do Mural, um cartão por vez; o Tocando Agora do macOS mostra a faixa.
  Na primeira vez o macOS pede acesso ao Apple Music. Sem assinatura, aparece a oferta da Apple;
  "Abrir no Música" leva ao app. Apagar o cartão ou fechar o mural para a música.
- **Página**: capa grande, Tocar e Abrir no Música e, em álbuns e playlists, as faixas; clicar numa
  faixa toca a partir dela. Faixa copiada ou link colado sem capa ganham a capa do catálogo depois
  que o acesso é dado.
- Uma playlist sua chega só com o nome: o Mural a procura na biblioteca ao tocar e avisa se houver
  duas com o mesmo nome.
- Murais com música usam a versão 8 do formato.

## Fotos e integrações nativas

- **Fotos…**, na barra de criação, abre o seletor do sistema para imagens e vídeos. A seleção é múltipla, preserva a âncora e a pasta capturadas antes do seletor e não pede acesso global à biblioteca. O Mural recebe arquivos por staging cancelável dentro do sandbox, preserva HEIC/HEIF quando a representação fornece esse tipo e mostra falhas parciais sem desfazer os itens concluídos.
- Arquivos, Lembretes e Apple Music seguem os caminhos públicos já implementados. Calendário e Contatos continuam como snapshots planejados, sem sincronização viva. Notas, Mail, Mensagens e outros apps sem API pública de leitura geral só entram por copiar/colar, compartilhar, arrastar ou arquivos fornecidos pelo usuário.
- O inventário completo de permissões, limites do sandbox e alternativas está em [`Docs/NativeIntegrations.md`](Docs/NativeIntegrations.md). O protocolo de baseline e os signposts de performance estão em [`Docs/PerformanceBaseline.md`](Docs/PerformanceBaseline.md).

## Barra de menus

- **Ícone do Mural na barra de menus**, enquanto o app está aberto (mesmo sem janela): abre um painel
  de vidro com a **vitrine dos murais**, em 3D como o Cover Flow, com reflexo. Cada capa mostra o mural
  inteiro, desenhada com os próprios cartões; as laterais ficam escurecidas, mais a cada passo para longe
  do centro, e a do centro, sem véu, é a escolhida. O centro começa no último mural usado pelo painel;
  senão, no da aba ativa; senão, no editado por último. ← → ou dois dedos trocam de mural, digitar
  letras procura pelo nome e Return abre o mural do centro. Visualizar › Abrir Painel de Murais abre o mesmo painel no meio da tela.
- **⌘` de qualquer app** abre e fecha o painel (outra combinação, ou nenhuma, nos Ajustes). Com dois
  Mural abertos, só o que mostra o ícone responde ao atalho.
- **Arrastar o painel** pelo fundo o muda de lugar, e ele reabre ali; nos Ajustes dá para desligar
  isso ou voltar o painel para junto do ícone.
- **Colar sem abrir a janela**, em etapas: o painel abre na vitrine, sem nenhuma forma de colar
  escolhida, e a linha "Copiado" mostra o que está na área de transferência. **Tab** mostra as formas
  de colar, as mesmas do ⌘V (Sticker, Card de texto ou Lista para texto; link, imagem, PDF, arquivos e
  música como eles são), com ↑ ↓ para escolher e Return para colar. Com texto, **outro Tab** mostra a
  formatação antes de colar: como está, limpar espaços, juntar linhas, lista com marcadores, lista de
  tarefas, minúsculas ou MAIÚSCULAS, com a prévia do resultado. ⇧Tab volta uma etapa e Esc volta à
  vitrine (nela, fecha o painel). ⌘V cola direto, em qualquer etapa, com o que estiver escolhido. O
  cartão entra no mural do centro, a capa se atualiza e o painel fecha. Clicar na capa do centro, ⌘↩
  ou "Abrir mural" abrem o mural no app.
- **Privacidade**: ao abrir, o painel só vê o tipo do que foi copiado, sem ler o conteúdo, e o macOS
  não pergunta nada. O conteúdo é lido na hora de colar: pelo ⌘V, sempre sem pergunta; pelo Return,
  o macOS pode pedir licença até o Mural ter permissão de colar nos Ajustes do Sistema (Privacidade e
  Segurança). Com a permissão, o painel já mostra a prévia ao abrir. O que vem marcado como privado,
  como senhas, nunca é lido.
- O painel cola pela aba quando o mural está aberto; fechado, o mural é aberto por um instante, gravado
  e fechado, e uma aba aberta nesse meio-tempo assume o lugar, sem perder o cartão. As capas ficam em
  `BoardCovers/`, ao lado dos murais, e são refeitas quando o mural muda.
- **Sem janela, fora do Dock**: com a janela fechada, o Mural sai do Dock e fica só o ícone na barra de
  menus; abrir um mural pelo painel (ou o app pelo Finder) traz a janela, o Dock e os menus de volta.
  Com mais de um Mural aberto (o instalado e uma cópia de desenvolvimento), só um mostra o ícone: o de
  Aplicativos e, entre cópias, o aberto há mais tempo.
- **Ajustes** (a engrenagem do painel, ⌘, ou Mural › Ajustes…): na aba Geral, **Abrir ao Iniciar
  Sessão** (começa desligado; também no menu Mural), com o qual o Mural fica só na barra de menus, sem
  janela, e **Sair do Mural**; na aba Painel, o atalho e o lugar do painel. Se o macOS pedir,
  "Permitir nos Ajustes do Sistema…" leva aos Itens de Início de Sessão.

## Murais compartilhados pelo iCloud

- **Compartilhar** (botão da barra da janela, ou Arquivo › Compartilhar…): o popover mostra o estado da
  sincronização e quem tem acesso. **Convidar pessoas…** abre o convite do iCloud: por link ou para pessoas
  escolhidas, com permissão por pessoa (editar ou só ver). Quem recebe abre o link e o mural aparece no Mac.
- **Só o mural posto no iCloud sincroniza**; os outros continuam só no Mac. O mural da pessoa no iCloud
  aparece em todos os Macs dela. Cada mural é uma zona do CloudKit, sincronizada pelo `CKSyncEngine`, sem
  servidor próprio e dentro do sandbox. Parar de compartilhar só tira as pessoas; **Tirar do iCloud…** deixa o
  mural só neste Mac; quem recebeu pode **Sair do mural compartilhado**.
- **Live Share**: numa chamada do FaceTime (ou chamando pessoas pela folha do sistema), quem foi convidado
  vê o cursor, o arrasto e o cartão aberto de cada pessoa. A presença é imediata; o conteúdo continua indo
  pelo iCloud e chega em poucos segundos por edição. Quem está na chamada sem convite não vê nem envia nada e
  pode pedir acesso.
- **Cópias no iCloud Drive**: a pasta Mural do iCloud Drive guarda uma cópia (`.mural`) de cada mural da
  pessoa; os recebidos de outras pessoas não. Só o Mac onde o mural mudou regrava a cópia, e ela só sai da
  pasta quando a pessoa exclui o mural. Abrir uma cópia pelo Finder abre o mural, se ele está no Mac. Dá para
  desligar em Ajustes › Geral (as cópias que já existem ficam).
- **Duas edições ao mesmo tempo** se juntam campo a campo: texto por linha, lista por item; o que não
  dá para juntar vira uma cópia de conflito, sem perder o que cada pessoa escreveu.
- **Só leitura**: quem só pode ver recebe as mudanças das outras pessoas, mas nada do que faz muda o
  mural compartilhado. Frases curtas, prévias de link e capas de música continuam de cada Mac.
- **Antes de cada TestFlight ou envio à loja com campo novo no iCloud**: num build de desenvolvimento,
  Arquivo › Preparar o Esquema do iCloud…, e depois "Deploy Schema Changes" no CloudKit Console
  (container `iCloud.com.joaocosta.Mural`). Sem isso, compartilhar falha em produção.
- Os testes usam um iCloud em memória; o app aberto só para hospedar os testes não sincroniza. Com
  `-uiTesting -liveShareDemo` (só em desenvolvimento) duas pessoas simuladas entram no Live Share, para
  conferir a interface sem chamada. Convite e Live Share de verdade só se conferem com duas contas do iCloud
  (notas para a revisão em `Docs/AppReviewNotes.md`).

## Requisitos

- macOS 27 e Xcode 27.2 ou mais novo (o projeto usa o formato JSON `project.xcproj`).
- O pacote [StretchText](https://github.com/joaaosc/StretchText), baixado do GitHub pelo Swift
  Package Manager (a partir da 1.0.0 no `MuralKit` e da 1.0.2 no projeto do app).
- Para a escolha das frases pelo modelo: um Mac com Apple Intelligence ligada. Sem ela,
  o app funciona com a primeira frase.
- Para tocar e listar faixas do Apple Music: o serviço MusicKit ligado no App ID do app
  (developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › App Services ›
  MusicKit). Sem ele o build passa e o cartão aparece, mas tocar mostra um erro.
- Para o iCloud: o App ID com iCloud (CloudKit e iCloud Documents, container `iCloud.com.joaocosta.Mural`),
  Push Notifications e Group Activities (SharePlay), e um perfil de provisionamento que inclua tudo (um build
  com `-allowProvisioningUpdates` os registra). Sem o entitlement do CloudKit, a sincronização fica desligada;
  sem o do iCloud Documents, não há cópias no iCloud Drive. A pasta Mural só aparece no iCloud Drive depois
  de o número da build subir (`CLOUD_BUILD_NUMBER`).

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `Packages/MuralKit` | Domínio sem interface: modelos, importação, gravação, paleta, estado observável, junção de edições (`MuralKit`) e sincronização com o iCloud (`MuralSync`). |
| `Mural/` | App: telas organizadas por área (`Tabs`, `Board`, `Collection`, `Detail`, `Cards`, `Chrome`, `Navigation`, `Input`, `Media`, `Style`, `MenuBar` com o painel da barra de menus, `Covers` com as capas da vitrine e `Cloud` com a ligação ao iCloud). |
| `MuralTests/` | Testes do app com Swift Testing. |
| `MuralUITests/` | Testes de interface que abrem o app com um mural de teste isolado. |
| `Config/Project.xcconfig` | Configurações de build comuns a todos os alvos. |
| `scripts/` | Verificação completa e conferência do arquivo de projeto. |

Os dados ficam em `~/Library/Containers/com.joaocosta.Mural/Data/Library/Application Support/Mural`:
cada mural é um pacote em `Boards/<id>.mural/` (`manifest.json`, `board.json` e `Items/` com as cópias dos
arquivos colados). Ao lado ficam `BoardCovers/` (capas da vitrine), `LinkPreviews/` (imagens das prévias),
`Sync/` (o que este Mac sabe de cada mural no iCloud) e `Backups/` (cópia de um mural antes de ir ao iCloud).

## Comandos

```sh
scripts/verify.sh          # formatação, projeto, domínio, build e testes do app
UI=1 scripts/verify.sh     # inclui os testes de interface (exigem o modo de automação)
scripts/ui-tests.sh        # só os de interface; esperam o Mac ficar livre de outros testes
swift test --package-path Packages/MuralKit
MURAL_RUNTIME_TESTS=1 swift test --package-path Packages/MuralKit --filter KeySentenceRuntimeTests  # modelo real
xcodebuild -project Mural.xcodeproj -scheme Mural -destination 'platform=macOS' build
swift format -i -r Mural MuralTests MuralUITests Packages/MuralKit/Sources Packages/MuralKit/Tests
scripts/release.sh 1.1.0             # release: versão, tag e envio da main com a tag (pergunta antes de enviar)
scripts/release.sh 1.0.6 --stable    # tag terminada em -stable; --check só confere, --no-push não envia
```

## Release

- **Um comando**: `scripts/release.sh <versão>` sobe `CLOUD_MARKETING_VERSION` em `Config/Project.xcconfig`, faz o
  commit, cria a tag e envia a `main` e a tag juntas (`git push --atomic`); o Xcode Cloud faz a build de release ao
  receber a tag, com o número de build dele.
- **Qual tag vira release** (a mesma regra no script e no Xcode Cloud, em `ci_scripts/release_rules.sh`): `vX.Y.Z` que
  sobe o major ou o minor, que tem o patch 5 ou que termina em `-stable`. O script recusa as outras antes de enviar.
- **Pelo Xcode**: Xcode › Ajustes › Comportamentos › **+**, dê um nome (e um atalho, se quiser) e marque "Executar" com
  `scripts/xcode-release.sh`. Ele pergunta a versão numa janela, mostra quantos commits vão subir, pede a confirmação e
  avisa o resultado numa notificação; o registro fica em `$TMPDIR/mural-release.log`.
- Sem tag, a build por commit do Xcode Cloud usa a versão de `Config/Project.xcconfig`.

## Convenções

- Regras de negócio ficam em `MuralKit`, com testes; o app só monta telas e liga ao sistema.
- O arquivo de projeto muda só por `xcrun xcodeproj`, nunca à mão. Arquivos novos de código
  entram sozinhos, porque as pastas do app são sincronizadas com o disco.
- `scripts/verify.sh` passa antes de cada commit.
- Commits pequenos e coesos, mensagem em português com até três linhas, descrevendo a mudança.
- Nenhum arquivo de mídia de teste é versionado; os testes geram as imagens de que precisam.
- Nos testes (e com `-disableOnDeviceModel`), o modelo do aparelho fica desligado: a frase
  curta é sempre a primeira, para nada mudar sozinho no meio de uma verificação.
