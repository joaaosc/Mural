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
| Baselines | `MuralTests/PerformanceBaselineTests` e `ThumbnailPerformanceTests` em Release com `ENABLE_TESTABILITY=YES` | XCTest performance/memória e resultado `.xcresult`/log | valores só são comparáveis em execuções pareadas, no mesmo estado |
| CPU | xctrace **Time Profiler**, 15 s, app Release com fixture | `.trace`, TOC e log de gravação | amostragem não é perfil completo nem p50/p95 |
| Alocações | xctrace **Allocations** | `.trace` e TOC | crescimento observado requer cenário/interação controlados |
| Leaks | xctrace **Leaks**, `leaks` e `heap` quando autorizados | trace e saída das ferramentas | TCC, símbolos e estado do processo podem impedir diagnóstico |
| Memória virtual | `vmmap -summary` | snapshot do processo e log | um snapshot não prova ausência de retenção ou pressão |
| Sanitizers | tentativas independentes de AddressSanitizer e ThreadSanitizer via `xcodebuild` | logs e códigos de saída | incompatibilidade do ambiente deve ficar inconclusiva |
| Hangs | xctrace **Hangs**/triage em uma coleta dedicada | trace triado com interação contínua | o script atual não inventa interação; a coleta manual é pendente |
| Crashes | `log show` e `~/Library/Logs/DiagnosticReports` após o início da auditoria | logs e lista de `.ips`/`.crash` | ausência local não exclui crashes em produção |
| MetricKit | `MuralMetricKitProbe` e coleta de payloads em execução | payload/diagnóstico entregue por MetricKit | a compilação do probe não confirma entrega diária |
| Organizer | métricas de distribuição e diagnósticos do Xcode Organizer | dados de usuários/elegibilidade | não substituível por build local |

## Critérios

As comparações devem usar o mesmo commit, configuração Release, máquina, fixture e sequência de interação. O baseline existente usa como sinais de investigação mediana >10%, p95 >15%, pico de memória >10% ou writes lógicos >10%, sempre preservando a variação da execução. Esses limiares são gates de revisão, não garantias de impacto em produção.

O script não encerra uma auditoria como verde quando o app não inicia, não há PID anexável, o empacotamento do Instruments falha, ou ferramentas como `leaks`/`vmmap` são bloqueadas. Cada caso aparece como `inconclusive` no relatório.

## Referências Apple

Documentação da Apple usada como referência:

- [Improving your app’s performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [MetricManager](https://developer.apple.com/documentation/metrickit/metricmanager)
- [Monitoring app performance with MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)

Uma captura local não demonstra assinatura, sandbox, TCC, App Store, hardware, entrega de notificações, dados de produção ou comportamento visual. Esses gates permanecem explicitamente pendentes quando não houver evidência própria.
