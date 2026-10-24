# Baseline e performance

Performance é validada por cenário e por evidência, não por uma afirmação geral de que o build passou.

## Cenários da primeira medição

As fixtures devem conter 100, 500 e 2.000 cards, com 10%, 50% e 90% de mídia, HEIC/JPEG/PNG, vídeos, PDFs, pastas aninhadas, notas com anexos, links com e sem prévia, lembretes e músicas. `PerformanceBoardFixture` em `Packages/MuralKit/Sources/MuralKit/Fixtures/PerformanceBoardFixture.swift` gera esses perfis com IDs, datas, metadados e posições determinísticos.

Essa primeira fixture é apenas um corpus estrutural: nomes de mídia, previews e artwork não correspondem a assets reais e nenhum arquivo binário é criado. Ela serve para medir contagem, hierarquia, layout e metadados. `ThumbnailPerformanceTests` acrescenta um cenário separado que gera temporariamente um PNG determinístico de 2048×1536 para medir decode/redução ImageIO; ele não representa ainda a variedade de fotos, vídeos, PDFs ou I/O de um mural real.

Medir cold launch, warm launch/resume, primeira tela interativa, mural e pasta grandes, scroll, zoom, marquee, arraste para pasta, importação de lote, thumbnails, prévias, autosave, fechar/reabrir e save/reopen do pacote.

## Métricas e critérios

Executar em Release, com cinco aquecimentos e dez repetições na mesma máquina e no mesmo estado de dados. Guardar tempo até primeira tela e interação, p50/p95, CPU, memória de pico e em suspensão, alocações/leaks, I/O, energia, rede e hitches/hangs.

Uma regressão é sinalizada quando a mediana piora mais de 10%, o p95 mais de 15%, a memória de pico mais de 10% ou os writes lógicos mais de 10%, sempre comparando com a variação do baseline.

## Observabilidade atual

`MuralSignposts` possui categorias para lançamento, leitura, persistência, importação, mídia, prévias e restauração. Os intervalos registram somente o nome da operação e valores agregados; não registram título de mural, texto, URL, caminho, nome de arquivo, contato, evento ou identificador externo.

Os pontos de baixo risco já instrumentados incluem cópia de arquivos, cópia tipada do PhotosPicker, gravação de imagens, autosave, restauração de canvas, decode de miniatura, aplicação de prévias de links e gravação de artwork de música. O próximo passo é correlacionar esses intervalos com as fixtures, sem concluir desempenho a partir de uma única execução.

## Próximos spikes

- MetricKit: o `MuralMetricKitProbe` valida, no macOS 27, a compilação e o cancelamento de duas observações independentes (`metricReports` e `diagnosticReports`). Ele não é criado pelo app, não lê nem persiste payloads e não envia dados; a entrega real de relatórios continua pendente de uma validação explícita em execução.
- Culling/virtualização: só depois de medir custo do `ZStack`/coleção; preservar seleção, arraste, z-order, VoiceOver, foco, Reduce Motion e restauração.
- Thumbnails: medir hit rate, decode, bytes residentes e primeiro desenho antes de trocar ImageIO/AVAssetImageGenerator por outro componente.

### Spike MetricKit

`Mural/App/MuralMetricKitProbe.swift` mantém um único `MetricManager` e, quando `start()` é chamado explicitamente por uma futura validação, cria uma `Task` para cada sequência de relatórios. `start()` é idempotente; `stop()` cancela ambas as tarefas e também é idempotente. O tipo não está ligado a `MuralApp`, ao delegate, ao lançamento normal, à UI ou ao modelo de dados.

O spike registra somente eventos agregados de chegada (`Metric report observed` e `Diagnostic report observed`). Não acessa títulos, URLs, caminhos, IDs ou qualquer outro campo dos relatórios, e não tem armazenamento local nem transporte de rede. A compilação confirma apenas a integração da API e a forma do ciclo de vida cancelável; não confirma a entrega de payloads reais, a frequência diária dos relatórios ou comportamento de produção.

Referências Apple: [Improving your app’s performance](https://sosumi.ai/documentation/xcode/improving-your-app-s-performance), [Writing and running performance tests](https://sosumi.ai/documentation/xcode/writing-and-running-performance-tests), [MetricManager](https://sosumi.ai/documentation/metrickit/metricmanager), [metricReports](https://sosumi.ai/documentation/metrickit/metricmanager/metricreports), [diagnosticReports](https://sosumi.ai/documentation/metrickit/metricmanager/diagnosticreports), [Monitoring app performance with MetricKit](https://sosumi.ai/documentation/metrickit/monitoring-app-performance-with-metrickit) e [Applying Liquid Glass to custom views](https://sosumi.ai/documentation/swiftui/applying-liquid-glass-to-custom-views).

### Ciclo executado em 2026-10-24

As orientações de manter `body` rápido, evitar cálculos derivados repetidos e comparar um perfil posterior com o anterior foram aplicadas em dois pontos sem alterar a hierarquia ou as features da interface:

- `85d20c0`: o cache de miniaturas passou a cancelar somente o consumidor que saiu, cancelar o trabalho compartilhado quando não há consumidores e evitar decodificação/cache prematuros de imagens originais.
- `7691b07`: `BoardCanvasView` reutiliza o array de cartões já calculado no `body`; `CollectionView` calcula uma vez por avaliação os filhos, cartões de coluna e post-its posicionados.
- `80992e4`: o target `MuralTests` passou a linkar o produto `StretchText` que os próprios testes importam, permitindo validar os testes focados.
- `800646e`: `PerformanceBaselineTests` passou a medir, com `XCTClockMetric` e `XCTMemoryMetric`, leitura da hierarquia e codificação JSON de uma fixture determinística de 500 cards com 50% de mídia. A fixture é criada fora da janela medida para separar custo de preparação do cenário.
- `ThumbnailPerformanceTests`: o decode/redução de um PNG temporário é medido sem adicionar asset ao repositório; a preparação e a remoção ficam fora da janela medida.
- `397f9aa` e `c6f347d`: `ReminderPickerSheet` passou a filtrar e particionar lembretes numa única passagem por avaliação, e o resumo de conteúdo passou de uma varredura por tipo para uma contagem acumulada; a ordem e os textos foram preservados por testes.
- `afabf76`: `BoardModel` passou a memoizar destinos de pasta para os menus e gestos que consultam vários cartões durante a mesma versão do mural; o cache é invalidado a cada mudança do board e os consumidores da UI passaram a usar esse caminho.
- `BoardModel` também memoiza `rootItems`, `freeTexts` e `children(of:)` durante a mesma versão do mural; cada getter continua lendo `board` para preservar o rastreamento de observação do SwiftUI, qualquer mutação invalida todos os derivados e os caches por pasta ficam limitados a 16 entradas FIFO.
- `MuralTests/PerformanceBaselineTests`: o cenário de Release passou a medir 200 consultas repetidas de destinos já memoizados e leituras repetidas de derivados do board, mantendo a preparação dos caches fora das janelas medidas.

Evidências verificadas após as mudanças:

- build macOS do app `com.joaocosta.Mural`: passou;
- `swift test --package-path Packages/MuralKit`: passou;
- `ThumbnailCacheTests`: 7/7 passaram;
- `PhotoImportDiagnosticsTests`: 7/7 passaram;
- `PerformanceBaselineTests`: 3/3 passaram em Release com `ENABLE_TESTABILITY=YES` somente no comando de teste; as leituras derivadas memoizadas mediram tempo monotônico médio de 0,000003 s e pico físico de memória médio de 28.073,378 kB, e o cenário de 200 consultas de destinos sob o limite FIFO mediu 0,067 s e 32.261,152 kB, sempre nas cinco iterações. O cenário estrutural marcou 0,005 s e 34.161,696 kB. Esses números são baselines da execução atual, não uma comparação antes/depois; o pico físico varia com o processo e deve ser comparado em execuções pareadas.
- `ThumbnailPerformanceTests`: 1/1 passou em Release com `ENABLE_TESTABILITY=YES` somente no comando de teste; o cenário mediu tempo monotônico médio de 0,011 s e pico físico de memória médio de 35.914,784 kB nas cinco iterações.
- `ReminderPickerTests` e `MuralTests`: 9/9 passaram após as reduções de recomputação.
- `BoardModelTests`: 19/19 passaram, incluindo invalidação dos caches depois de criar uma nova pasta, cartão e texto livre.
- formatter do projeto e `scripts/check-xcproj.sh`: sem diferenças ou erros.

A suíte macOS completa ultrapassou o link depois da correção de produto, mas foi interrompida após 22 casos com três falhas de runtime do ambiente; não é considerada verde. A primeira gravação de 10 segundos com `xctrace` atingiu o limite de coleta, mas o empacotador do Instruments falhou ao salvar o trace por não conseguir obter `~/Library/Application Support/Instruments/Packages/lock`. Depois de liberar artefatos gerados, uma gravação Debug foi salva em `/tmp/Mural-performance-launch.trace`; `xctrace show` mediu CPU média agregada de 5,9%, mínimo de 0%, máximo de 140% e desvio de 19%. O mesmo cenário em Release foi compilado com sucesso e salvo em `/tmp/Mural-performance-launch-release.trace`, com CPU média de 7,0%, mínimo de 0%, máximo de 150% e desvio de 21,3%. Esses números são apenas baselines de lançamento desta execução e não representam uma redução percentual nem medem interação com um mural grande. O próximo gate é repetir o cenário Release antes/depois com uma fixture carregada e comparar Time Profiler/SwiftUI, Allocations, File Activity e Energy Log.

A primeira tentativa de executar `PerformanceBaselineTests` em Release parou antes da compilação porque o alvo de aplicação foi produzido sem `-enable-testing` (`Mural.swiftmodule` incompatível com `MuralTests`). A medição foi repetida com `ENABLE_TESTABILITY=YES` como override transitório apenas no comando de teste; passou sem modificar a configuração Release global, a assinatura ou as configurações de distribuição do app. Os valores acima são uma baseline estrutural inicial, não uma comparação antes/depois nem uma medição de interação visual.
