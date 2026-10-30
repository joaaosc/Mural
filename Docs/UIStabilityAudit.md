# Auditoria de estabilidade e Liquid Glass

Revisão de 29–30/10/2026 sobre a versão 1.7.5 (`9b370c8`). A leitura do código e os testes abaixo se concentram no canvas, pastas, imagens, miniplayer, barras e painel. Não constituem homologação de todas as telas ou garantia de ausência de glitches.

O diagnóstico posterior, as correções do recorte visual e as comparações de desempenho em Release estão em [PerformanceDiagnosis.md](PerformanceDiagnosis.md). Os números e limites abaixo permanecem como registro da rodada anterior.

## Resultado

A fundação visual revisada usa Liquid Glass nativo: `.glassEffect`, estilos de botão SwiftUI, `GlassEffectContainer` e `NSGlassEffectView` no painel que hospeda a árvore SwiftUI. AppKit é uma integração nativa apropriada para esse painel macOS. Cartões de conteúdo e fundos de leitura não precisam receber Liquid Glass para que o aplicativo seja nativo.

Foram corrigidos três riscos em quatro arquivos, com dois commits:

- `0db8407`: protege limpeza e cancelamento dos gestos de arrasto.
- `bab6664`: usa a transição de vidro adequada ao vão do miniplayer.

As correções funcionais passaram nos testes listados abaixo. **O desempenho não está aprovado:** a medição revelou atrasos relevantes, e a captura adicional com Instruments apresentou consumo excessivo de memória, seguido de kernel panic do sistema. As evidências e os limites estão separados nas próximas seções.

A rodada foi concluída após a retomada, com **46 testes aprovados**, sem falhas nem alertas de runtime nos resumos. As correções estão na `main` local, em commits separados; não foi feito push nem instalada uma nova versão de distribuição. As alterações anteriores foram preservadas. O diagnóstico dos atrasos permanece pendente e impede considerar o desempenho global homologado.

## Achados corrigidos

| Arquivo | Risco anterior | Alteração |
| --- | --- | --- |
| `Mural/Board/BoardCanvasView.swift` | A limpeza do gesto criava uma tarefa independente, sem cancelamento ao começar outra interação ou sair da view. Uma execução atrasada podia apagar o deslocamento ou tamanho de um gesto posterior. | Limpeza com `.task(id: isDragging)`, suspensão cooperativa e conferência de cancelamento/inatividade antes de limpar os estados transitórios. |
| `Mural/Collection/CollectionView.swift` | Mesmo padrão de tarefa independente ao limpar o arrasto do post-it dentro da pasta. | Limpeza vinculada a `isDraggingSticky`, cancelada ao mudar sua identidade ou desaparecer a view. |
| `Mural/Chrome/NowPlayingBar.swift` | Deslocamento e indicador temporários dependiam de `onEnded` para serem limpos. Cancelamento sem esse evento podia deixar a barra deslocada ou os cliques bloqueados. | `@GestureState` para os dois valores; destino final calculado com a translação do evento final, independentemente da ordem de reset do estado transitório. |
| `Mural/Chrome/NowPlayingExpanded.swift` | `.matchedGeometry` para uma forma inserida com vão de 10 pt dentro de um contêiner com distância de fusão zero. | `.materialize`, conforme a recomendação para efeitos além da distância de fusão. Preservada `.identity` com Reduzir Movimento. |

As corridas de limpeza são riscos identificados na leitura do código. Não foi capturada uma reprodução pareada da corrida antes/depois. Os testes reais demonstram funcionamento dos caminhos normais após a alteração; não demonstram todos os cancelamentos possíveis.

Não foram alterados persistência, modelos de domínio, entitlements, App Sandbox, versão ou arquivo de projeto. Não foram introduzidas dependências nem abstrações novas.

## Documentação oficial confrontada com o código

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): formas personalizadas, ordem dos modificadores, agrupamento de efeitos relacionados e transição `materialize` quando a inserção ocorre além da distância de fusão. Também recomenda limitar o número de efeitos e contêineres simultâneos.
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview): vidro nativo do AppKit, com `contentView`, cantos, estilo e tinta. Em `PanelGlass.swift`, o conteúdo SwiftUI está no hospedeiro nativo; não foi adicionado outro vidro por cima.
- [GestureState](https://developer.apple.com/documentation/swiftui/gesturestate): estado temporário atualizado em `updating`, com reset automático quando o gesto deixa de estar ativo.
- [task(id:name:priority:file:line:_:)](https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)): cancelamento e recriação por mudança de identidade, além de cancelamento associado à saída da view. O código verifica cancelamento explicitamente, pois ele é cooperativo.
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): reduzir dependências e atualizações desnecessárias, evitar trabalho custoso no `body` e medir antes de atribuir ganhos a mudanças de código.

## Mecanismos revisados e preservados

- Canvas com recorte dos elementos fora da área visível, margem de pré-carregamento, histerese e cache da seleção renderizada. Elementos envolvidos em interações continuam presentes. Esse modelo não foi substituído por uma pilha preguiçosa genérica.
- Miniaturas assíncronas, pedidos em andamento compartilhados, limite de concorrência e cache com custo. Não foi encontrada decodificação síncrona direta no `body` revisado.
- Efeitos Metal de pasta/revelação desativados nas posições de repouso. Eles animam conteúdo; não substituem o material Liquid Glass das barras.
- Painel com um hospedeiro de vidro, recorte de cantos e tratamento de Reduzir Transparência/Aumentar Contraste. Preservado o recorte que corrige a borda quadrada.
- Barras com vidro de grupo e botões nativos ou sem borda. Não foi aplicada interatividade de vidro indiscriminadamente ao grupo inteiro de botões.
- Leitura dos caminhos principais em `RootView`, `HeroContext`, `CollectionView`, `LinkDetailView`, `MusicDetailView`, `MuralWindowView`, `BoardFocus`, `CardEmphasis`, `ResizeCornerPointer`, controles do miniplayer e coverflow. A leitura não equivale a exercitar todas as combinações dessas telas.

## Verificação antes do reinício

### Estado e geometria

38 testes em quatro suítes passaram: `BoardFocusTests`, `CanvasRenderCullingTests`, `NowPlayingPlacementTests` e `FolderHoverShrinkTests`. O resumo não indicou alertas de runtime.

Não houve mudança nos modelos do pacote; a suíte completa de domínio não foi repetida.

### Build e metadados

Build/testes Debug aprovados. `swift format lint --strict` nos quatro arquivos, `scripts/check-xcproj.sh` e `git diff --check` aprovados. A configuração de distribuição e os entitlements foram preservados; não houve nova auditoria de assinatura/App Store.

### UI real

Cinco testes passaram, sem falhas:

- `testDraggingCardMovesItAndKeepsPosition`.
- `testDraggingStickyInsideFolderPlacesItFreely`.
- `testImageResizeFromTopLeadingKeepsOppositeCorner`.
- `testMiniPlayerSnapsToDockAndRemembersIt`.
- `testExpandedPlayerTogglesShuffleAndRepeat`.

Foram inspecionadas capturas da foto após redimensionamento e do miniplayer expandido à direita. As imagens mostraram o recorte arredondado da foto, a alça junto da borda e o vão entre o player expandido e a pílula. Capturas estáticas não demonstram todos os quadros da animação.

Essa inspeção ocorreu em aparência escura. Aparência clara, VoiceOver, Reduzir Movimento e Reduzir Transparência não foram exercitados em runtime nesta rodada; os ramos de código relevantes foram revisados.

### Desempenho em Release

O teste `testPerformanceFixtureScrollAndZoom` executou cinco iterações sobre uma fixture estrutural de 2.000 cartões. Cada iteração contém três ciclos de rolar/voltar/aproximar/afastar. A execução terminou com sucesso e sem alertas de runtime no resumo.

| Métrica por iteração | Média | Intervalo observado |
| --- | --- | --- |
| Tempo total | 21,289 s | 20,926–21,514 s |
| CPU do aplicativo | 12,357 s | 11,552–13,343 s |
| Pico de memória física | 529,169 MB decimais | 529,123–529,205 MB |
| Atrasos de renderização | 126,2 | 114–142 |
| Proporção de atraso | 265,872 ms/s | 219,916–311,533 ms/s |
| Escritas lógicas | 480,870 kB | 413,696–544,768 kB |

**Execução aprovada não significa fluidez aprovada.** O resultado tinha referência de comparação igual a zero, sem base pareada para detectar regressão. Os atrasos são relevantes. A carga concorrente do Mac variou durante a rodada, portanto não há base para anunciar ganho percentual ou atribuir todos os atrasos ao aplicativo.

O uso de `accessibilityEnabled` para forçar a presença de todos os cartões é uma variável a separar: a automação pode ampliar a árvore renderizada. Isso é uma hipótese a verificar, não uma causa comprovada. Não foi retirada acessibilidade para melhorar o número do teste.

A primeira tentativa Release falhou antes da execução porque o alvo de testes não conseguiu importar o módulo do app. A repetição usou `ENABLE_TESTABILITY=YES`, opção já utilizada pelo script de desempenho do repositório, apenas no comando de teste. Não foi alterada a configuração de distribuição.

## Falha do perfilamento e kernel panic

Uma rodada adicional do mesmo teste passou em 191,719 s, com captura de 20 s pelo instrumento SwiftUI. Seus tempos não são comparáveis ao benchmark, pois a instrumentação adiciona custo.

O perfilador não concluiu a exportação legível. O arquivo apresentou erro de documento sem template nas tentativas de leitura. Após mais de cinco minutos, houve tentativa de interrupção com `SIGINT`; ela não encerrou o processo antes da falha posterior do sistema.

O registro local `panic-full-2026-10-29-231558.0002.panic` contém:

- Kernel panic por ausência de resposta do `watchdogd` durante 90 s.
- Processo em panic: `kernel_task`.
- 14 arquivos de swap e indicação de pouco espaço disponível para swap.
- `xctrace`, PID 87547, com 16.352.737.608 bytes de memória residente, o maior consumidor listado no momento da falha. É o PID da captura desta rodada.

Essa evidência sustenta que o perfilamento contribuiu fortemente para a pressão de recursos. Não prova, sozinho, a causa única do kernel panic, nem permite atribuir a falha ao código do Mural. Não existe traço legível para identificar a view responsável pelos atrasos. Não repetir a mesma captura sem um procedimento com limites de recursos e preservação do diagnóstico.

Na primeira conferência após o reinício, os dois commits continuavam intactos; não havia processos de teste/perfilamento ativos. A sessão normal do Mural foi preservada. O sistema ainda apresentava carga muito alta, por isso os testes foram adiados até a retomada descrita abaixo.

### Disponibilidade das evidências

Os resultados e capturas da rodada estavam em `/tmp/mural-ui-audit-*`. Esse diretório temporário foi limpo no reinício, inclusive o relatório preliminar e a captura SwiftUI. Os números e resultados acima foram obtidos e conferidos antes da interrupção, mas os bundles e imagens não estão mais disponíveis para nova inspeção. Este documento é o registro persistente; não apresentar os caminhos temporários antigos como evidência ainda acessível.

Há registros locais anteriores de CPU do Mural em execução de testes, inclusive um relatório de 22:19 com aproximadamente 97% de CPU por 93 s. Ele precede esta auditoria e não demonstra regressão causada por estes commits.

## Verificação final após a retomada

Com o sistema recuperado, a instância normal do Mural foi encerrada pelo comando normal do aplicativo, sem encerramento forçado. O verificador de exclusividade de testes liberou a execução. Não foi iniciada outra captura com Instruments nem repetida a carga de 2.000 cartões.

Foram realizadas duas execuções sequenciais em Debug, com destino explícito `platform=macOS` e `-parallel-testing-enabled NO`:

| Resultado persistente | Casos | Resultado |
| --- | --- | --- |
| `Verification.xcresult` | 38 testes nas quatro suítes de estado/geometria e os cinco testes de UI descritos acima | 43 aprovados; zero falhas, casos ignorados ou alertas de runtime |
| `GroupAndResize.xcresult` | Três testes adicionais de UI descritos abaixo | 3 aprovados; zero falhas, casos ignorados ou alertas de runtime |

O resumo de build da primeira execução também informou zero erros, avisos de compilação e avisos do analisador. A segunda execução usou `test-without-building`, com o mesmo produto recém-compilado. Os três casos adicionais foram:

- `testDroppingSelectionOnFolderStoresBothCards`: seleciona dois cartões, guarda ambos na pasta e confirma sua presença ao reabrir o aplicativo de teste.
- `testImageResizeSnapsToPhotoProportionAndRepeats`: confere o encaixe em 4:3 e o segundo arrasto a partir do tamanho novo.
- `testImageResizeWithZoomSnapsPortraitPhoto`: confere o encaixe em 3:4 com zoom de 1,25×, mantendo a origem.

Os bundles, logs e nove capturas exportadas estão preservados em `~/Library/Logs/Mural/UIStabilityAudit-20261029/`. As capturas estão nas pastas `Attachments/` e `GroupAndResizeAttachments/`, acompanhadas dos respectivos manifestos. Esses arquivos são evidências locais e não fazem parte do repositório.

Foram inspecionadas novamente as imagens da foto após arrasto pelo canto superior, do player expandido à direita, da foto depois do segundo arrasto e da foto em pé com zoom. Nas duas últimas, a alça permanece junto do canto inferior direito e o recorte arredondado acompanha o tamanho novo. O player apresenta cantos arredondados e vão visível entre as superfícies. Isso confirma os quadros capturados em aparência escura; não comprova todos os quadros de animação ou variantes de acessibilidade.

`swift format lint --strict` nos quatro arquivos alterados, `scripts/check-xcproj.sh` e `git diff --check` passaram novamente. Nenhum arquivo de projeto, entitlement, workflow local ou configuração de distribuição foi alterado.

O escopo desta entrega é a auditoria e as correções locais descritas, com suas verificações. Não existe nova medição pareada de desempenho após o reinício e não se afirma ganho de CPU, memória ou fluidez. O resultado anterior com atrasos exige uma investigação separada e controlada antes de qualquer aprovação de desempenho.

## Riscos, confiança e próximos passos

- Confiança nas correções locais: **85%**, apoiada por build, testes de geometria/estado e interação real. O cancelamento no meio de um gesto por perda de foco não teve reprodução automatizada específica.
- Confiança para declarar o desempenho global satisfatório: **baixa**. Há atrasos medidos, falta comparação pareada e o perfilamento falhou com consumo excessivo de recursos. A investigação de desempenho permanece aberta.
- Priorizar uma reprodução pequena e controlada dos atrasos; diferenciar árvore acessível, trabalho do app, composição gráfica e custo da automação. Começar com menos cartões e amostragem limitada, com destino persistente para resultados e limites de recursos. Não repetir diretamente a captura que consumiu 16 GB.
- Depois, exercitar variantes de acessibilidade/aparência, cancelamento de arrasto por perda de foco, múltiplas janelas e grandes pastas com mídia real.
- O histórico local menciona sobreposição de post-it com pasta em hover. Não foi reproduzida nesta rodada; preservar a política intencional de empilhamento até existir cenário isolado e teste de regressão.
- Não houve refatoração ampla nem remoção de funcionalidades para simplificar o código. Nenhuma mudança de mecanismo de renderização foi justificada por ganho presumido.

## Como verificar novamente

Somente com o sistema estável e sem outros testes ou instância normal do app aberta: executar `scripts/check-tests-idle.sh ui`, usar destino explícito `platform=macOS` e selecionar os testes relevantes com `-only-testing`. Preservar dados da sessão normal; não forçar encerramento nem descartar conteúdo.

Para testes Release que importam o app, usar `-configuration Release ENABLE_TESTABILITY=YES` apenas na execução. Guardar `-resultBundlePath` em diretório persistente fora de `/tmp`. Não iniciar nova captura SwiftUI nas mesmas condições da falha descrita acima.
