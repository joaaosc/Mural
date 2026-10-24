# Integrações nativas

Este inventário separa o que o Mural já implementa, o que depende de uma permissão do sistema e o que permanece como roadmap. Nenhuma integração lê containers privados de outro app, usa AppleScript como bypass do sandbox ou grava identificadores externos sem uma decisão de produto.

## Disponível

### Fotos

O botão **Fotos…** usa `PhotosPicker` com imagens e vídeos, seleção múltipla e `preferredItemEncoding: .current`. O sistema entrega somente os itens escolhidos; a primeira versão não pede acesso global à biblioteca. Cada item é recebido por `FileRepresentation`, copiado para staging em `Caches` e só então classificado por `UTType` e comprometido em `Items/`. Falhas individuais aparecem no estado de erro do mural; itens concluídos não são desfeitos.

O staging é cancelável e validado contra o mural, a aba, a pasta e a época da apresentação capturados antes do seletor. Live Photo é tratada pela representação still nesta versão. Falhas de download de iCloud Photos são reportadas por item.

Referências Apple: [PhotosPicker](https://sosumi.ai/documentation/photosui/photospicker), [PhotosPickerItem](https://sosumi.ai/documentation/photosui/photospickeritem), [FileRepresentation](https://sosumi.ai/documentation/coretransferable/filerepresentation) e [Bringing Photos picker to your SwiftUI app](https://sosumi.ai/documentation/photokit/bringing-photos-picker-to-your-swiftui-app).

### Arquivos

`Arquivo › Importar…`, arrastar e soltar e a área de transferência usam os tipos suportados pelo `ContentClassifier`: imagens, vídeos, PDFs e texto. O acesso ao arquivo é concedido pela ação explícita do usuário e a cópia é feita dentro do container do Mural.

### Lembretes

O Mural usa EventKit para listar os lembretes escolhidos e guardar um snapshot no card. A primeira ação que precisa da biblioteca pede `NSRemindersFullAccessUsageDescription`; negar ou revogar o acesso não apaga o snapshot já salvo. O card não apaga o lembrete no app de origem.

### Apple Music

Links, pasteboard e arrastar do Música alimentam os cards de Apple Music. Catálogo, biblioteca/playback, ausência de assinatura, autorização negada, item removido, rede indisponível e falha de artwork são estados distintos. O serviço MusicKit precisa estar habilitado no App ID para playback e catálogo.

## Roadmap controlado

### Calendário

Uma futura importação será um snapshot textual: calendários e intervalo escolhidos pelo usuário, recorrências materializadas somente nesse intervalo, título, data/hora, fuso, dia inteiro e nome do calendário. Não haverá sincronização viva nem consulta automática de todo o histórico. Antes de implementar, será usado um fake de EventKit para autorização negada/revogada, store indisponível, calendário removido, recorrência e alteração durante o commit.

### Contatos

Uma futura importação será um snapshot textual dos contatos escolhidos, com nome exibido e, opcionalmente, um telefone, email e organização. Os `CNKeyDescriptor`s serão mínimos; foto, endereço, aniversário, nota e identificadores locais ficam fora da primeira versão. A consulta ocorrerá fora da main thread. Revogar o acesso não apaga cópias que o usuário já colocou no mural.

## Fontes sem API pública de leitura apropriada

Notas, Mail, Mensagens, histórico/abas do Safari, Livros, Voice Memos, Podcasts, TV, Mapas, Casa, Saúde e Carteira não são lidos por containers privados ou scraping. Os caminhos suportados são copiar/colar, arrastar anexos, `NSSharingService`, `fileImporter`, abrir o app de origem e importar links ou formatos públicos já suportados.

O produto não promete áudio, EPUB, `.ics` ou `.vcf` enquanto o `ContentClassifier` não tiver suporte explícito a esses formatos.

## Permissões e sandbox

Permissões só são solicitadas no momento da ação que precisa delas. A build mantém App Sandbox e os entitlements de arquivos/serviços existentes; a validação de assinatura deve conferir o `Info.plist` e os entitlements do produto gerado, não apenas o manifesto do projeto. Dados pessoais, títulos, URLs, caminhos e identificadores externos não entram em logs ou signposts.
