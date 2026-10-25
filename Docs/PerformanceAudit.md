# Auditoria local de performance

Esta auditoria automatiza uma coleta local reproduzível sem transformar um build verde em uma afirmação sobre o runtime. O script não altera a biblioteca normal do usuário: o cenário manual usa `-manualTesting -performanceFixture`, que é isolado pelo app em `MuralPerformanceTests`.

## Execução

```sh
scripts/performance-audit.sh [diretório-de-saída]
```

Sem argumento, os artefatos ficam em `/tmp/mural-performance-audit-<timestamp>`. O relatório Markdown, logs, status do worktree, `.trace` e o app Release ficam nesse diretório; nada é gravado no repositório além do próprio script e desta documentação.

O relatório deve separar sempre:

- **Verificado:** o comando terminou com sucesso e o artefato esperado foi produzido.
- **Inconclusivo:** a ferramenta, permissão, TCC, processo, build ou ambiente impediu a medição; não é evidência de ausência de problema.
- **Pendente:** a medição exige outra condição, interação, dispositivo, dados ou coleta de produção.

## Matriz de evidências

| Área | Medição local | Evidência aceitável | Limite da conclusão |
| --- | --- | --- | --- |
| Domínio | `swift test --package-path Packages/MuralKit` | testes verdes e logs preservados | não mede SwiftUI, I/O real ou hardware |
| Baselines | `MuralTests/PerformanceBaselineTests` e `ThumbnailPerformanceTests` em Release com `ENABLE_TESTABILITY=YES`, sanitizers desligados e DerivedData isolado | XCTest performance/memória e resultado `.xcresult`/log | valores só são comparáveis em execuções pareadas, no mesmo estado |
| Interação | `MuralUITests/testPerformanceFixtureScrollAndZoom`, cinco iterações sobre 2.000 cartões | CPU, memória, storage, hitches e relógio do processo `Mural` | TCC ou indisponibilidade de UI automation deixa a etapa inconclusiva |
| CPU | xctrace **Time Profiler**, 15 s, app Release com fixture | `.trace`, resumo de CPU e call tree invertida | a captura automatizada mede repouso; a interação é coberta separadamente pelo XCTest |
| Alocações | xctrace **Allocations** | `.trace` e TOC | crescimento observado requer cenário/interação controlados |
| Leaks | xctrace **Leaks**, `leaks` e `heap` quando autorizados | trace e saída das ferramentas | TCC, símbolos e estado do processo podem impedir diagnóstico |
| Memória virtual | `vmmap -summary` | snapshot do processo e log | um snapshot não prova ausência de retenção ou pressão |
| Sanitizers | AddressSanitizer e ThreadSanitizer em suítes funcionais separadas via `mobilebuildmcp` | logs e códigos de saída | ASan não detecta leaks; o overhead dos sanitizers invalida números de performance |
| Hangs | xctrace **Hangs**/triage em uma coleta dedicada | trace triado com interação contínua | o script atual não inventa interação; a coleta manual é pendente |
| Crashes | `log show` e `~/Library/Logs/DiagnosticReports` após o início da auditoria | logs e lista de `.ips`/`.crash` | ausência local não exclui crashes em produção |
| MetricKit | `MuralMetricKitProbe` e coleta de payloads em execução | payload/diagnóstico entregue por MetricKit | a compilação do probe não confirma entrega diária |
| Organizer | métricas de distribuição e diagnósticos do Xcode Organizer | dados de usuários/elegibilidade | não substituível por build local |

## Critérios

As comparações devem usar o mesmo commit, configuração Release, máquina, fixture e sequência de interação. O baseline existente usa como sinais de investigação mediana >10%, p95 >15%, pico de memória >10% ou writes lógicos >10%, sempre preservando a variação da execução. Esses limiares são gates de revisão, não garantias de impacto em produção.

O script não encerra uma auditoria como verde quando o app não inicia, não há PID anexável, o empacotamento do Instruments falha, ou ferramentas como `leaks`/`vmmap` são bloqueadas. Cada caso aparece como `inconclusive` no relatório.

O Power Profiler da documentação atual da Apple é uma medição em iPhone ou iPad físico. Para este app macOS, a evidência local usa métricas por processo do XCTest, Time Profiler, Allocations/Leaks, snapshots do processo e o Energy gauge. Comparações devem ser pareadas, repetidas e feitas no mesmo Mac; uma indicação momentânea “High CPU Utilization” não demonstra carga sustentada sem o intervalo e a call tree correspondentes.

## Ordem de diagnóstico

1. Rodar o script uma vez no commit de referência e preservar todo o diretório de artefatos.
2. Tratar primeiro falhas funcionais e sanitizers; não comparar performance de uma execução inválida.
3. Comparar as métricas Release do mesmo cenário. Investigar regressões, não apenas valores absolutos isolados.
4. Abrir `time-profiler-calltree.md` e o `.trace` quando CPU ou hitches piorarem; otimizar apenas stacks do processo Mural com custo relevante.
5. Usar Allocations/Leaks, `heap` e `vmmap` para distinguir leak, retenção, cache deliberado e memória virtual.
6. Repetir a coleta depois de uma única mudança e comparar antes/depois na mesma máquina.
7. Complementar com Organizer e MetricKit; dados locais não representam automaticamente usuários ou máquinas diferentes.

## Referências Apple

Documentação da Apple usada como referência:

- [Improving your app’s performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [Scheduling CPU work efficiently](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently)
- [Analyzing CPU profiles with call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views)
- [Analyzing your app’s battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use)
- [Measuring your app’s power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)
- [Gathering information about memory use](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use)
- [Making changes to reduce memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)
- [Preventing memory use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions)
- [Diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)
- [Investigating memory access crashes](https://developer.apple.com/documentation/xcode/investigating-memory-access-crashes)
- [Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
- [Analyzing the performance of your shipping app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-shipping-app)
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [MetricManager](https://developer.apple.com/documentation/metrickit/metricmanager)
- [Monitoring app performance with MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)

Uma captura local não demonstra assinatura, sandbox, TCC, App Store, hardware, entrega de notificações, dados de produção ou comportamento visual. Esses gates permanecem explicitamente pendentes quando não houver evidência própria.
