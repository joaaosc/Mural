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
    /// - Novo de um lado só, entra. As seções novas do `remote` vão para o fim da lista, e os itens novos do `remote` para o fim da
    ///   seção em que estão lá. Se a seção de um item saiu, ele vai para a que o outro lado deu a ele, senão para a primeira que
    ///   sobrou; se nenhuma sobrou, a seção vem junto.
    /// - Na estrutura, quem mexeu vence: quem só moveu ou reordenou itens não perde a mudança quando a outra pessoa marca um item e
    ///   regrava a lista. A seção de um item é a do lado que a mudou; mudada nos dois lados, ou em nenhum, a do `local`. A ordem das
    ///   seções, e a dos itens dentro de cada seção, é a do lado que a mudou; mudada nos dois, ou em nenhum, a do `local`, e o que só
    ///   o `remote` tem vai para o fim. A ordem de um lado só compara os ids que ele e a base têm em comum.
    /// - Cada `id` aparece uma vez só no resultado.
    public static func merge(base: ChecklistDocument, local: ChecklistDocument, remote: ChecklistDocument) -> ChecklistDocument? {
        guard let intro = TextMerge.merge(base: base.intro, local: local.intro, remote: remote.intro) else { return nil }

        let baseIndex = Index(base)
        let localIndex = Index(local)
        let remoteIndex = Index(remote)
        guard let keptTitles = sectionTitles(base: baseIndex, local: localIndex, remote: remoteIndex),
            let entries = mergedEntries(base: baseIndex, local: localIndex, remote: remoteIndex)
        else { return nil }

        var titles = keptTitles
        var order = ordered(
            local: localIndex.sectionIDs, remote: remoteIndex.sectionIDs, base: baseIndex.sectionIDs, keeping: { keptTitles[$0] != nil })

        // Em que seção fica cada item, na ordem do local e depois na do remote. Se a seção dele saiu, vale a do outro lado, depois a
        // primeira que sobrou e, sem nenhuma, a seção de onde ele veio passa a existir.
        var placement: [UUID: UUID] = [:]
        var assigned: [UUID: [UUID]] = [:]
        for id in localIndex.entryIDs + remoteIndex.entryIDs where entries[id] != nil && placement[id] == nil {
            guard let wanted = wantedSections(of: id, base: baseIndex, local: localIndex, remote: remoteIndex) else { continue }
            let home: UUID
            if titles[wanted.preferred] != nil {
                home = wanted.preferred
            } else if let other = wanted.other, titles[other] != nil {
                home = other
            } else if let first = order.first {
                home = first
            } else {
                let origin = localIndex.sections[wanted.preferred] ?? remoteIndex.sections[wanted.preferred]
                titles[wanted.preferred] = origin?.title ?? ""
                order.append(wanted.preferred)
                home = wanted.preferred
            }
            placement[id] = home
            assigned[home, default: []].append(id)
        }

        let sections = order.map { sectionID in
            let inOrder = ordered(
                local: localIndex.entryIDsBySection[sectionID] ?? [], remote: remoteIndex.entryIDsBySection[sectionID] ?? [],
                base: baseIndex.entryIDsBySection[sectionID] ?? [], keeping: { placement[$0] == sectionID })
            // Quem foi para esta seção só porque a dele saiu não está em nenhuma ordem e fica no fim.
            let known = Set(inOrder)
            let ids = inOrder + (assigned[sectionID] ?? []).filter { !known.contains($0) }
            return ChecklistSection(id: sectionID, title: titles[sectionID, default: ""], entries: ids.compactMap { entries[$0] })
        }

        let title = local.title != base.title ? local.title : remote.title
        return ChecklistDocument(title: title, intro: intro, sections: sections)
    }

    // MARK: Interno

    /// A lista indexada pelo `id`: cada seção e cada item, com a seção em que o item está, e a ordem de tudo. Com `id` repetido (dado
    /// corrompido) vale o primeiro, como no resto do pacote.
    private struct Index {
        var sectionIDs: [UUID] = []
        var sections: [UUID: ChecklistSection] = [:]
        var entryIDs: [UUID] = []
        var entries: [UUID: (entry: ChecklistEntry, sectionID: UUID)] = [:]
        var entryIDsBySection: [UUID: [UUID]] = [:]

        init(_ document: ChecklistDocument) {
            for section in document.sections {
                if sections[section.id] == nil {
                    sections[section.id] = section
                    sectionIDs.append(section.id)
                }
                for entry in section.entries where entries[entry.id] == nil {
                    entries[entry.id] = (entry, section.id)
                    entryIDs.append(entry.id)
                    entryIDsBySection[section.id, default: []].append(entry.id)
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

    /// A seção de um item: a do lado que o moveu, e `other` é a do outro lado, se ele também tem o item. Movido nos dois lados, ou
    /// em nenhum, vale a do `local`. Um item que a base não tinha conta como movido nos lados que o têm.
    private static func wantedSections(of id: UUID, base: Index, local: Index, remote: Index) -> (preferred: UUID, other: UUID?)? {
        let original = base.entries[id]?.sectionID
        switch (local.entries[id]?.sectionID, remote.entries[id]?.sectionID) {
        case (let mine?, let theirs?):
            return mine == original && theirs != original ? (theirs, mine) : (mine, theirs)
        case (let only?, nil), (nil, let only?):
            return (only, nil)
        case (nil, nil):
            return nil
        }
    }

    /// Os ids que `wanted` aceita, na ordem do lado que a mudou em relação à base. Mudada nos dois lados, ou em nenhum, vale a do
    /// `local`. Depois dela vêm os ids que só o outro lado tem, na ordem dele.
    private static func ordered(local: [UUID], remote: [UUID], base: [UUID], keeping wanted: (UUID) -> Bool) -> [UUID] {
        let remoteLeads = isReordered(remote, from: base) && !isReordered(local, from: base)
        var seen = Set<UUID>()
        return (remoteLeads ? remote + local : local + remote).filter { wanted($0) && seen.insert($0).inserted }
    }

    /// A ordem mudou em relação à base. Só os ids que os dois têm contam: apagar ou acrescentar não reordena.
    private static func isReordered(_ side: [UUID], from base: [UUID]) -> Bool {
        let inBase = Set(base)
        let inSide = Set(side)
        return side.filter(inBase.contains) != base.filter(inSide.contains)
    }
}
