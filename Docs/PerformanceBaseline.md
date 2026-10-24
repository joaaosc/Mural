# Baseline e performance

Performance é validada por cenário e por evidência, não por uma afirmação geral de que o build passou.

## Cenários da primeira medição

As fixtures devem conter 100, 500 e 2.000 cards, com 10%, 50% e 90% de mídia, HEIC/JPEG/PNG, vídeos, PDFs, pastas aninhadas, notas com anexos, links com e sem prévia, lembretes e músicas. `PerformanceBoardFixture` em `Packages/MuralKit/Sources/MuralKit/Fixtures/PerformanceBoardFixture.swift` gera esses perfis com IDs, datas, metadados e posições determinísticos.

Essa primeira fixture é apenas um corpus estrutural: nomes de mídia, previews e artwork não correspondem a assets reais e nenhum arquivo binário é criado. Ela serve para medir contagem, hierarquia, layout e metadados. Decode, thumbnail, I/O e custos de mídia real exigem um corpus separado de arquivos representativos, a ser adicionado antes das medições correspondentes.

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
