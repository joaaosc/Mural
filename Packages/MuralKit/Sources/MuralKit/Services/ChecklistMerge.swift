import Foundation

/// Junta duas edições da mesma lista feitas a partir da mesma base, item a item.
///
/// Numa lista de compras, uma pessoa marca "leite" e outra marca "pão" ao mesmo tempo, e as duas marcações precisam ficar, sem
/// virar conflito. Por isso a junção compara cada seção e cada item pelo `id`, e não a lista inteira como um bloco só.
public enum ChecklistMerge {
    /// A lista com as edições dos dois lados, ou `nil` quando alguma não entra sem desfazer o que a outra pessoa fez.
    ///
    /// - Título da lista: mudado só de um lado, vale esse; mudado dos dois, o do `local`. A abertura passa pela `TextMerge`, e se ela
    ///   colide a lista inteira é um conflito.
    /// - Seções e itens casam pelo `id`. Mudado só de um lado, vale esse; mudado para o mesmo valor, ele. A marcação (`isDone`) mudada
    ///   dos dois jeitos fica a do `local`, assim como o título de uma seção. O texto de um item mudado dos dois jeitos é conflito.
    /// - Apagado de um lado e intocado do outro, sai; apagado de um lado e alterado do outro é conflito. Só o conteúdo conta como
    ///   alteração (o título da seção, o texto e a marcação do item), não a posição.
    /// - Novo de um lado só, entra. A ordem é a do `local`: as seções novas do `remote` vão para o fim da lista, e os itens novos do
    ///   `remote` para o fim da seção em que estão lá. Se essa seção saiu, vão para a primeira que sobrou; se nenhuma sobrou, a seção
    ///   vem junto.
    /// - Item que está em seções diferentes nos dois lados fica na do `local`. Cada `id` aparece uma vez só no resultado.
    public static func merge(base: ChecklistDocument, local: ChecklistDocument, remote: ChecklistDocument) -> ChecklistDocument? {
        guard let intro = TextMerge.merge(base: base.intro, local: local.intro, remote: remote.intro) else { return nil }

        let baseIndex = Index(base)
        let localIndex = Index(local)
        let remoteIndex = Index(remote)
        guard let titles = sectionTitles(base: baseIndex, local: localIndex, remote: remoteIndex),
            let entries = mergedEntries(base: baseIndex, local: localIndex, remote: remoteIndex)
        else { return nil }

        var sections: [ChecklistSection] = []
        var position: [UUID: Int] = [:]
        // As seções que ficam: as do local, na ordem dele, e depois as novas do remote.
        for section in local.sections + remote.sections {
            guard let title = titles[section.id], position[section.id] == nil else { continue }
            position[section.id] = sections.count
            sections.append(ChecklistSection(id: section.id, title: title, entries: []))
        }

        var placed = Set<UUID>()
        // Primeiro os itens do local que continuam na seção que têm lá, na ordem dele.
        for section in local.sections {
            guard let index = position[section.id] else { continue }
            for entry in section.entries {
                guard let merged = entries[entry.id], placed.insert(entry.id).inserted else { continue }
                sections[index].entries.append(merged)
            }
        }

        // Depois o que ficou sem lugar vai para o fim de uma seção. Quando a que ele pedia saiu, vale a primeira que sobrou e, sem
        // nenhuma, a seção de onde ele veio passa a existir.
        func append(_ entry: ChecklistEntry, preferring sectionID: UUID, from origin: ChecklistSection) {
            if sections.isEmpty {
                position[origin.id] = 0
                sections.append(ChecklistSection(id: origin.id, title: origin.title, entries: []))
            }
            sections[position[sectionID] ?? 0].entries.append(entry)
        }
        // Itens do local cuja seção saiu: seguem para a seção que o remote deu a eles, se houver.
        for section in local.sections {
            for entry in section.entries {
                guard let merged = entries[entry.id], placed.insert(entry.id).inserted else { continue }
                append(merged, preferring: remoteIndex.entries[entry.id]?.sectionID ?? section.id, from: section)
            }
        }
        // Itens novos do remote, na ordem dele.
        for section in remote.sections {
            for entry in section.entries {
                guard let merged = entries[entry.id], placed.insert(entry.id).inserted else { continue }
                append(merged, preferring: section.id, from: section)
            }
        }

        let title = local.title != base.title ? local.title : remote.title
        return ChecklistDocument(title: title, intro: intro, sections: sections)
    }

    // MARK: Interno

    /// A lista indexada pelo `id`: cada seção e cada item, com a seção em que o item está. Com `id` repetido (dado corrompido) vale
    /// o primeiro, como no resto do pacote.
    private struct Index {
        var sections: [UUID: ChecklistSection] = [:]
        var entries: [UUID: (entry: ChecklistEntry, sectionID: UUID)] = [:]

        init(_ document: ChecklistDocument) {
            for section in document.sections {
                if sections[section.id] == nil { sections[section.id] = section }
                for entry in section.entries where entries[entry.id] == nil {
                    entries[entry.id] = (entry, section.id)
                }
            }
        }
    }

    /// O título de cada seção que continua na lista, ou `nil` se alguma foi apagada de um lado e renomeada no outro.
    private static func sectionTitles(base: Index, local: Index, remote: Index) -> [UUID: String]? {
        var titles: [UUID: String] = [:]
        for id in Set(local.sections.keys).union(remote.sections.keys) {
            let original = base.sections[id]?.title
            switch (local.sections[id], remote.sections[id]) {
            case (let mine?, let theirs?):
                titles[id] = mine.title != original ? mine.title : theirs.title
            case (let only?, nil), (nil, let only?):
                // Sem a seção do outro lado: se ela estava na base, foi apagada lá e só sai se ninguém a renomeou.
                guard original == nil || only.title == original else { return nil }
                if original == nil { titles[id] = only.title }
            case (nil, nil):
                break
            }
        }
        return titles
    }

    /// Cada item que continua na lista, já junto, ou `nil` se algum é um conflito: texto mudado dos dois jeitos, ou item apagado de
    /// um lado e alterado no outro.
    private static func mergedEntries(base: Index, local: Index, remote: Index) -> [UUID: ChecklistEntry]? {
        var merged: [UUID: ChecklistEntry] = [:]
        for id in Set(local.entries.keys).union(remote.entries.keys) {
            let original = base.entries[id]?.entry
            switch (local.entries[id]?.entry, remote.entries[id]?.entry) {
            case (let mine?, let theirs?):
                guard let entry = mergedEntry(base: original, local: mine, remote: theirs) else { return nil }
                merged[id] = entry
            case (let only?, nil), (nil, let only?):
                // Sem o item do outro lado: se ele estava na base, foi apagado lá e só sai se ninguém o alterou.
                guard let original else {
                    merged[id] = only
                    continue
                }
                guard only.text == original.text, only.isDone == original.isDone else { return nil }
            case (nil, nil):
                break
            }
        }
        return merged
    }

    /// O item nos dois lados: cada campo vale o de quem o mudou. Sem a base (o item é novo nos dois lados), a marcação é a do
    /// `local` e os textos precisam ser iguais.
    private static func mergedEntry(base: ChecklistEntry?, local: ChecklistEntry, remote: ChecklistEntry) -> ChecklistEntry? {
        let text: String
        if local.text == remote.text || remote.text == base?.text {
            text = local.text
        } else if local.text == base?.text {
            text = remote.text
        } else {
            return nil
        }
        return ChecklistEntry(id: local.id, text: text, isDone: local.isDone != base?.isDone ? local.isDone : remote.isDone)
    }
}
