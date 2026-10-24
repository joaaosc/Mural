# MetricKit: lifecycle e validação local

O probe continua experimental e ausente do lançamento normal. A alteração não habilita
telemetria, persistência, rede ou leitura de campos dos relatórios.

## Contrato

- Um único MetricManager é retido pelas duas observações durante a vida do probe.
- `start()` retorna true ao iniciar e false em running/stopping; não enfileira reinício.
- `await stop()` cancela e aguarda as duas tarefas. Chamadas concorrentes compartilham
  a drenagem. Cancelar o chamador não libera os iteradores prematuramente.
- Enquanto uma sequência não terminar, state permanece stopping. Não há timeout que
  libere novos iteradores sobre uma observação ainda viva.
- Se uma sequência terminar naturalmente, a outra continua ativa. Quando ambas terminam,
  state volta a stopped e é possível iniciar outra sessão.
- As tarefas não retêm o probe; deinit solicita cancelamento. Isso não substitui
  `await stop()` quando é necessário aguardar uma parada ordenada.
- state, metricReportCount e diagnosticReportCount são consultáveis no MainActor.
  Os contadores são cumulativos, saturados em Int.max e vivem somente em memória.
  Callbacks de sessões anteriores, após cancelamento ou durante parada são ignorados.
- Os logs contêm somente o tipo de chegada. Não contêm payload, caminho, título, URL,
  identificadores externos ou o UUID interno usado para distinguir sessões.

Exemplo para harness de desenvolvimento, retendo o probe no dono do harness:

```swift
let probe = MuralMetricKitProbe()
probe.start()
// Manter o harness em execução para aguardar relatórios reais.
// Consultar probe.state e os dois contadores no MainActor.
await probe.stop()
probe.start() // só depois de a parada concluir
await probe.stop()
```

Não iniciar/parar a cada troca de aba/janela. O lifecycle pertence a um dono duradouro.
A primeira observação não implica entrega imediata; contadores zero não provam defeito.

## Trazer para o Mac

Na cópia local do repositório, com alterações locais preservadas, usar:

```sh
git fetch origin codex/metrickit-lifecycle
git switch --track origin/codex/metrickit-lifecycle
```

Para aplicar somente o commit em outra branch, usar o SHA informado na entrega com
`git cherry-pick SHA`. Não executar as duas opções se quiser aplicar a mudança uma única vez.
Esta branch contém apenas o probe, os testes e este documento.

## Checks no Mac

Requer Xcode/SDK compatível com o projeto (macOS 27 e Swift 6.4).
A partir da raiz do repositório:

```sh
swift format lint --strict Mural/App/MuralMetricKitProbe.swift MuralTests/MuralMetricKitProbeTests.swift
scripts/check-tests-idle.sh
xcodebuild -project Mural.xcodeproj -scheme Mural -destination 'platform=macOS' \
  -only-testing:MuralTests/MuralMetricKitProbeTests test
```

Os testes usam observações controladas para validar cancelamento, parada concorrente,
reinício, término natural, descarte do dono e contagem. Não esperam payloads diários.
Antes de integrar ao lançamento, validar com as sequências reais se cancelamento termina
os iteradores. Se não terminar, manter o probe em stopping e investigar a API; não remover
essa barreira para permitir restart.

## Evidência e pendências

Implementação preparada em Linux, sem Swift/Xcode. `git diff --check` passou; compilação,
formatação Swift e execução da suíte ainda não foram realizadas nesta sessão.
Nenhuma alegação de aprovação de testes Swift ou entrega real de relatórios.

Ainda dependem de execução em Mac: payload real, frequência, retenção caso venha a ser
implementada, StateReporting e medições Release/Instruments. Não há integração de
produção nesta mudança. PerformanceBaseline.md descreve a baseline; para o contrato
atual do probe, usar este documento.
