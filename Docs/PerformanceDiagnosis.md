# Diagnóstico de desempenho da interface

Data: 29–30 de outubro de 2026. Plataforma medida: Apple M1, 8 GB de memória, macOS 27.2 (26B123), Xcode 27.2 (27B48). Configuração Release, com `ENABLE_TESTABILITY=YES` para os testes. A medição usa o app de teste e uma biblioteca isolada; não altera os murais da biblioteca de uso diário.

Implementação: commit `7a4c465` em `main` — reduz as prévias fora da tela preservando a acessibilidade.

## Resumo

Foi confirmado um gargalo na construção e atualização da árvore visual do canvas: a presença de tecnologia assistiva ativava `forceAll` e construía as prévias completas dos cartões distantes. Isso anulava o recorte geométrico justamente no caminho observado pelos testes de interface. Não era apenas uma diferença de aparência do Liquid Glass.

A correção separa a presença acessível do cartão de sua prévia visual. Os botões, rótulos, ações e menus continuam disponíveis; as prévias custosas são construídas somente na região próxima da janela. Interações em andamento continuam incluídas, mesmo fora dessa região. O pré-carregamento passou de uma largura/altura de janela para meia largura/altura, mantendo uma margem maior que o limite que dispara a atualização do recorte.

Nas duas ordens de comparação, a correção reduziu o pico de memória em aproximadamente 41% e a quantidade de atrasos em 59%, na média das seis medições por modo. O ganho de CPU foi menor, cerca de 6%. A redução da duração dos atrasos variou muito e não se repetiu de forma relevante na segunda rodada. O cenário grande ainda apresenta atrasos de quadros; a interface inteira não está aprovada em desempenho.

## Evidências e causa confirmada

### Código e estado observado

O caminho anterior de `BoardCanvasView` passava `accessibilityEnabled` como `forceAll` ao cache. O cache devolvia todos os itens; cada um construía `CardView`, legendas e suas subárvores. Na amostra de 2.000 itens totais, havia 406 cartões na raiz. Sob a automação, a sonda registrou `accessibilityEnabled=true`, `forceAll=true` e 406 prévias, mesmo quando poucas dezenas estavam próximas da janela.

Esse sinal do ambiente significa que há uma tecnologia assistiva habilitada. Ele não significa especificamente que o VoiceOver está ligado. A documentação diferencia essas propriedades. A observação em testes não demonstra que todas as execuções normais usam esse caminho. Fonte: [accessibilityEnabled](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityenabled).

Com o recorte visual independente, a mesma janela de 1.240 × 800 pontos manteve os 406 cartões na árvore acessível e construiu 41 prévias no início, passando a 33 ou 39 após a sequência de interação nas duas rodadas. A pasta e o texto livre posicionados fora da região visível continuaram encontrados pela árvore de acessibilidade antes e depois da medição. Isso verifica sua presença; não substitui uma sessão completa de navegação por VoiceOver.

### Perfil de CPU

Uma captura de cinco segundos com Time Profiler registrou aproximadamente 2,92 segundos de CPU amostrada. Cerca de 2,87 segundos, ou 98,1%, estavam na linha principal, responsável pela interface. Entre os caminhos inclusivos mais relevantes estavam:

| Caminho | Tempo amostrado | Parcela das amostras |
| --- | ---: | ---: |
| `NSHostingView.layout` | 1,12 s | 38,2% |
| `GraphHost.flushTransactions` | 0,737 s | 25,2% |
| `AG::Subgraph::update` | 0,662 s | 22,7% |
| Construção de `CardButton` / `cardSurface` | 0,110 s | 3,8% |

Os caminhos se sobrepõem: seus percentuais não devem ser somados. O perfil aponta custo de atualização/layout do SwiftUI na linha principal; a comparação com a mesma interface e menos prévias confirma uma contribuição concreta desse excesso de trabalho. A captura não separa integralmente custo de CPU, composição e GPU, nem identifica cada dependência do grafo do SwiftUI.

A orientação da Apple é medir atualizações demoradas e atualizações frequentes, reduzir dependências e evitar cálculos repetidos no `body`. Esse diagnóstico segue essa distinção: o problema confirmado envolve o volume de elementos atualizados, e não apenas uma função isolada lenta. Fonte: [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

## Comparação reproduzível

O ensaio de comparação usa o mesmo executável Release, a mesma quantidade de itens, a mesma janela e a mesma sequência. Um modo de referência restaura as prévias completas e a margem anteriores; o outro usa a correção. Cada teste faz três medições de uma sequência de rolagem para cima, rolagem para baixo, aumento e redução do zoom. O Time Profiler não estava ativo durante as medições abaixo.

### Recorte visual e pré-carregamento

Resultados consolidados de `PairedVisuals.xcresult` e `PairedReverse.xcresult`. A segunda rodada inverteu a ordem: referência antes da correção. Valores são médias de seis medições por modo; MB são decimais, convertidos dos kB fornecidos pelo resultado do teste. O ganho é do conjunto de mudanças no recorte e no pré-carregamento; o ensaio não atribui uma porcentagem a cada mudança isoladamente.

| Métrica | Referência | Corrigido | Redução |
| --- | ---: | ---: | ---: |
| CPU do processo durante a sequência | 4,909 s | 4,624 s | 5,8% |
| Tempo decorrido da sequência | 6,854 s | 6,458 s | 5,8% |
| Pico de memória física | 537,6 MB | 317,7 MB | 40,9% |
| Tempo de atraso por segundo | 315,1 ms/s | 267,1 ms/s | 15,2% na média; ganho instável |
| Quantidade de atrasos | 48,0 | 19,7 | 59,0% |

O tempo de CPU é tempo acumulado de processamento, não porcentagem de uso da máquina. O tempo decorrido inclui a automação das interações. A taxa de atrasos mede conteúdo que perdeu o prazo de apresentação e não deve ser convertida diretamente em FPS. Fonte: [XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric).

O pico de memória ficou entre 525,7 e 554,0 MB na referência, e entre 281,6 e 345,3 MB com a correção, sem sobreposição entre as amostras. A quantidade de atrasos ficou entre 44 e 52 na referência, e entre 18 e 23 com a correção. São os ganhos mais consistentes desta medição.

A taxa de atrasos ficou entre 294,9 e 342,6 ms/s na referência e entre 165,3 e 385,4 ms/s com a correção. Na primeira rodada, a média caiu de 308,2 para 215,3 ms/s; na segunda, de 321,9 para 318,9 ms/s, praticamente sem ganho. Portanto, há menos eventos, mas alguns ainda são longos. Não é correto concluir que o tempo perdido em travamentos melhorou de forma estável. A variação de CPU também se sobrepõe entre os modos; o ganho médio pequeno não tem a mesma força da redução de memória. Seis amostras por modo não permitem estimar percentis ou uma margem estatística robusta.

Como controle diagnóstico, forçar apenas a árvore da região pré-carregada na segunda rodada produziu 1,858 s de CPU, 179,6 MB de pico e 69,5 ms/s de atrasos. Esse modo remove elementos distantes da árvore acessível e não foi adotado em produção. Ele mostra que ainda existe custo relevante nos controles mantidos para acessibilidade; não é uma prova de comportamento de uma execução comum sem automação.

### Versão final sem sondas

O teste permanente `testPerformanceFixtureScrollAndZoom` foi executado após remover os argumentos, modos e textos temporários de diagnóstico. Usa a amostra padrão de 2.000 cartões, sem o texto livre adicional. Foram cinco medições de três ciclos de rolagem e zoom por medição:

| Métrica | Média | Menor–maior medição |
| --- | ---: | ---: |
| CPU durante três ciclos | 12,889 s | 11,679–14,966 s |
| Tempo decorrido de três ciclos | 21,084 s | 20,345–22,688 s |
| Pico de memória física | 323,9 MB | 297,0–341,5 MB |
| Tempo de atraso por segundo | 247,4 ms/s | 208,1–313,7 ms/s |
| Quantidade de atrasos em três ciclos | 60,4 | 47–70 |

O teste passou e confirma o patamar de memória na versão final. A quantidade maior de ciclos impede comparar seus tempos brutos com os do ensaio curto. A taxa de atrasos continua elevada: a correção traz ganhos concretos, mas não resolve integralmente a fluidez do mural grande.

### Alcance da amostra

A amostra contém 2.000 cartões, dos quais 406 na raiz, e um texto livre de diagnóstico fora da região visível. Os demais cartões ficam em pastas; não são 2.000 cartões simultaneamente na tela. Os tipos e posições são determinísticos, mas os arquivos de mídia da amostra são estruturais: não representam a decodificação de uma biblioteca real de HEIC, JPEG, PDF e vídeo.

Uma execução anterior com 100 itens totais, 26 na raiz, apresentou aproximadamente 3 ms/s de atrasos e cerca de 100 MB de pico. O problema se torna importante na amostra maior. Essa rodada menor é contexto de escala, não uma comparação de ganho da versão final.

O computador tinha processos de sistema e aplicativos em segundo plano. Uma rodada intermediária coincidiu com instalação do sistema e foi excluída da comparação principal. A captura instrumentada também foi excluída. Usar o mesmo executável e repetir a comparação reduz diferenças de compilação e configuração, mas não elimina toda a variação de uma máquina em uso.

## Arquivos alterados

- `Mural/Board/CanvasRenderCulling.swift`: o cache distingue os itens que precisam permanecer acessíveis das prévias que precisam existir visualmente; preserva itens em interação e evita construir todas as prévias antes de chegar a primeira geometria válida.
- `Mural/Board/BoardCanvasView.swift`: distribui essa visibilidade às prévias dos cartões e dos textos livres. O tamanho total do plano de rolagem continua independente do número de prévias presentes.
- `Mural/Cards/CardButton.swift`: preserva o botão externo, identidade, rótulo, valor, seleção, ações e menu; omite apenas o conteúdo da prévia fora da região pré-carregada.
- `Mural/Board/BoardFreeTextView.swift`: preserva o rótulo completo e as ações de edição, tamanho e exclusão; omite o desenho do texto e do material fora da região pré-carregada.
- `MuralTests/CanvasRenderCullingTests.swift`: cobre separação entre acessibilidade e prévias, primeiro layout, preservação de interações e cobertura do pré-carregamento até o limite da atualização.
- `Docs/UIStabilityAudit.md`: aponta para este diagnóstico e conserva os resultados históricos.

A meia janela de pré-carregamento excede a tolerância de um quarto de janela usada para atualizar o recorte. O teste verifica os deslocamentos nas duas direções e a atualização ao ultrapassar o limite. Essa relação evita reduzir a margem sem proteção contra espaços vazios durante rolagem. Mudanças rápidas e amplas de posição ainda dependem do próximo ciclo normal de atualização da interface.

### Liquid Glass e App Sandbox

Os efeitos continuam usando as APIs nativas existentes, incluindo `glassEffect`, `GlassEffectContainer` e `NSGlassEffectView`. Não foi acrescentado um desfoque por cima do conteúdo nem substituído o vidro por uma simulação. Reduzir as prévias e o trabalho do canvas evita sobrecarregar a composição sem descaracterizar os controles.

A Apple orienta usar formas adequadas, aplicar o efeito após os modificadores de aparência e agrupar vidros relacionados em `GlassEffectContainer` para melhor desempenho de renderização. Esses pontos não autorizam espalhar vidro por cada cartão de conteúdo. Fonte: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

Não houve mudança de projeto, capabilities, assinatura ou entitlements. O App Sandbox permanece exigido.

## Verificação e artefatos

Os resultados desta rodada ficam em `~/Library/Logs/Mural/PerformanceDiagnosis-20261029/`, fora do diretório temporário apagado no reinício anterior.

| Nível de verificação | Resultado observado na versão final |
| --- | --- |
| Domínio e renderização isolada | 17 testes de recorte e três testes do efeito de encolhimento aprovados; incluem limites, revisão do cache, geometria transitória e renderização de pixels |
| Build e metadados | Release aprovado, zero erros e zero avisos; formatação Swift e forma canônica do projeto conferidas; assinatura verificada com `codesign --verify --deep --strict`; `com.apple.security.app-sandbox=true` no app gerado |
| UI real | Oito testes funcionais aprovados: abrir/voltar de pasta, mover com zoom, guardar dois cartões em pasta com persistência, redimensionar foto com persistência, redimensionar foto com zoom, preservar canto oposto, redimensionar sticker e selecionar/colorir/excluir vários cartões |
| Desempenho | Teste permanente aprovado com as métricas acima; perfil de CPU e duas ordens de comparação preservados separadamente |

O conjunto final teve **29 aprovações, zero falhas e zero alertas de runtime** no resumo dos testes. Foram inspecionadas três capturas em modo escuro: foto após arrasto pelo canto superior, foto em proporção vertical com zoom e sticker redimensionado. Nessas capturas, o cartão mantém os cantos arredondados e o sticker permanece limitado à sua caixa. As verificações de coordenadas e persistência vêm dos testes; as capturas não comprovam todas as variantes visuais do app. Não foram repetidas nesta rodada todas as telas em modo claro, com transparência reduzida ou com VoiceOver.

| Artefato | Utilidade |
| --- | --- |
| `PairedVisuals.xcresult` | Comparação no mesmo executável; duas aprovações, três medições por modo; presença acessível de elementos distantes verificada |
| `PairedReverse.xcresult` | Ordem invertida e controle de recorte; três aprovações, sem alertas de runtime |
| `PairedDiagnostic.patch` | Código do ensaio temporário, aplicável à base `df93677` em checkout separado; removido da versão final |
| `FinalValidation.xcresult` | Versão final: 29 aprovações, build sem avisos e benchmark permanente |
| `FinalAttachments/manifest.json` | Mapeamento das seis capturas exportadas aos testes de imagem e sticker |
| `VisualCulling.xcresult` | 17 testes do recorte aprovados; falhas iniciais do seletor de texto acessível corrigidas no ensaio seguinte |
| `BeforeCPU.trace` e `BeforeCPU-tree.md` | Perfil de CPU de cinco segundos e árvore de chamadas |
| `BeforeCPU.log` | Limites e consumo da captura |
| `Small.xcresult`, `Large.xcresult` | Escala inicial e diagnóstico do caminho de acessibilidade |

As falhas iniciais de seleção de texto vieram de procurar um elemento genérico de acessibilidade como `staticText`, inclusive na referência. A verificação passou a consultar o elemento pela identificação textual entre todos os tipos; a comparação principal passou nos dois modos. Outra tentativa inicial aguardava uma pasta distante ficar visível antes de iniciar o teste de recorte e foi descartada. Esses resultados não devem ser tratados como regressões confirmadas do app.

A captura atual foi limitada a cinco segundos, com interrupção automática por tempo e consumo dos processos monitorados do comando de captura. Terminou normalmente; esses processos atingiram aproximadamente 448 MiB de RSS. O instrumento SwiftUI que havia provocado forte pressão de memória na rodada anterior não foi repetido. Isso evita reproduzir deliberadamente a condição observada antes do reinício; não comprova a causa de um eventual panic do sistema.

## Como rodar

Para repetir a verificação do recorte sem abrir o Xcode:

```sh
scripts/check-tests-idle.sh ui
rtk xcodebuild -project Mural.xcodeproj -scheme Mural \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:MuralTests/CanvasRenderCullingTests test \
  -resultBundlePath "$HOME/Library/Logs/Mural/CullingVerification.xcresult"
```

Use um nome novo de resultado a cada execução. O teste permanente `MuralUITests/MuralUITests/testPerformanceFixtureScrollAndZoom` mede cinco repetições de três ciclos de interação. Seu tempo bruto não é comparável ao ensaio curto de três repetições de um ciclo usado para isolar a causa neste documento.

## Riscos e confiança

- **Confiança na correção local: 85%.** Há correspondência entre o estado registrado, o caminho do código, o perfil de CPU e a redução de memória nas duas ordens de comparação. A cobertura de mídia real e navegação assistiva completa ainda limita essa confiança.
- **Desempenho global: ainda insuficientemente comprovado.** A amostra grande corrigida ainda tem atrasos relevantes. Não existe evidência para afirmar fluidez constante em todos os murais ou ausência de gargalo de GPU.
- **Acessibilidade: preservação estrutural verificada, navegação completa pendente.** Elementos distantes continuam presentes e os controles mantêm ações e menus. Leitura, foco e ativação por VoiceOver precisam de uma rodada específica com a tecnologia assistiva em uso.
- **Mídia real e uso prolongado: pendentes.** A amostra não permite concluir sobre decodificação de imagens grandes, páginas PDF, vídeo, picos de importação, consumo ao longo de horas ou vazamentos. Esses limites são de cobertura da medição, não falhas demonstradas.
- **Pastas muito grandes e arrasto de centenas de cartões: não medidos.** Itens em interação permanecem incluídos para não desaparecerem durante o gesto. Um grupo muito grande pode aumentar o trabalho visual; o teste funcional desta rodada verifica dois cartões. Abertura de pastas com centenas de mídias e uso de várias janelas também precisam de medição própria.
- **Rolagem muito rápida:** reduzir mais a margem traria risco de aparecimento tardio de cartões. Foi mantida folga acima do limite de atualização e incluído teste geométrico; não foi escolhida a menor margem possível apenas para melhorar números.

O custo restante no caminho acessível demanda reduzir o trabalho dos controles distantes sem comprometer sua descoberta, foco e ativação. O controle diagnóstico mais rápido retira esses elementos da árvore e por isso não atende a esse requisito. Uma mudança mais ampla de representação precisa ser validada com navegação assistiva real; as verificações atuais comprovam a presença dos elementos, mas não homologam essa alternativa.

## Próximos passos

Priorizar uma amostra com arquivos reais e uma rodada de uso prolongado. Em seguida, separar rolagem, zoom e abertura de pasta em medições independentes, com mais repetições, para localizar o custo restante. Caso os atrasos persistam fora da automação, coletar CPU e apresentação de quadros de forma limitada e avaliar separar melhor as dependências do canvas. Não é indicado remover acessibilidade, animações ou vidro nativo para mascarar a métrica.

A auditoria visual anterior permanece em [UIStabilityAudit.md](UIStabilityAudit.md), com seus próprios resultados e limites históricos.
