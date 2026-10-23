import Foundation

/// Junta duas edições do mesmo texto feitas a partir da mesma base, linha a linha.
///
/// Serve para duas pessoas que mexeram na mesma nota ao mesmo tempo: se cada uma editou parágrafos diferentes, as duas edições
/// entram. Se mexeram no mesmo lugar, escolher uma delas seria apagar o que a outra escreveu, e por isso a junção devolve `nil` e
/// deixa quem chamou guardar as duas versões.
public enum TextMerge {
    /// O texto com as edições dos dois lados, ou `nil` quando elas colidem.
    ///
    /// Se os dois lados são iguais, ou só um deles mudou, vale o que mudou. Senão, cada lado é comparado com a base e os trechos
    /// que ele trocou são aplicados juntos sobre ela. Dois trechos colidem quando se sobrepõem, ficam colados na base ou inserem no
    /// mesmo ponto (como duas linhas novas no fim do texto); a única exceção são trechos idênticos, que entram uma vez só.
    ///
    /// As linhas se separam só por `"\n"` e as vazias contam, então a linha em branco entre parágrafos e o `"\n"` do fim do texto
    /// voltam como estavam.
    public static func merge(base: String, local: String, remote: String) -> String? {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }

        let baseLines = lines(of: base)
        let localEdits = edits(from: baseLines, to: lines(of: local))
        let remoteEdits = edits(from: baseLines, to: lines(of: remote))
        guard let bothEdits = combined(localEdits, remoteEdits) else { return nil }

        var merged: [Substring] = []
        var cursor = 0
        for edit in bothEdits {
            merged += baseLines[cursor..<edit.removed.lowerBound]
            merged += edit.inserted
            cursor = edit.removed.upperBound
        }
        merged += baseLines[cursor...]
        return merged.joined(separator: "\n")
    }

    // MARK: Interno

    /// Um trecho da base trocado por outro: as linhas que saem (`removed`, vazio numa inserção) e as que entram no lugar.
    private struct Edit: Equatable {
        var removed: Range<Int>
        var inserted: [Substring]
    }

    /// `"".split` devolve uma linha vazia, e juntar de volta com `"\n"` reproduz o texto, qualquer que seja ele.
    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Os trechos que levam `base` a `edited`, em ordem. Linhas removidas ou inseridas em sequência formam um trecho só, e entre dois
    /// trechos sempre sobra ao menos uma linha que não mudou.
    private static func edits(from base: [Substring], to edited: [Substring]) -> [Edit] {
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for step in edited.difference(from: base) {
            switch step {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }

        // As linhas que ficam aparecem na mesma ordem nos dois textos, então basta andar nos dois ao mesmo tempo: uma linha removida
        // só avança a base, uma inserida só avança o texto novo, e uma que ficou avança os dois e fecha o trecho aberto.
        var result: [Edit] = []
        var open: Edit?
        var baseIndex = 0
        var editedIndex = 0
        while baseIndex < base.count || editedIndex < edited.count {
            if baseIndex < base.count, removedOffsets.contains(baseIndex) {
                var edit = open ?? Edit(removed: baseIndex..<baseIndex, inserted: [])
                edit.removed = edit.removed.lowerBound..<(baseIndex + 1)
                open = edit
                baseIndex += 1
            } else if editedIndex < edited.count, insertedOffsets.contains(editedIndex) {
                var edit = open ?? Edit(removed: baseIndex..<baseIndex, inserted: [])
                edit.inserted.append(edited[editedIndex])
                open = edit
                editedIndex += 1
            } else {
                if let edit = open { result.append(edit) }
                open = nil
                baseIndex += 1
                editedIndex += 1
            }
        }
        if let open { result.append(open) }
        return result
    }

    /// Os trechos dos dois lados numa lista só, em ordem, ou `nil` se algum colide com o do outro lado. Os trechos de um mesmo lado
    /// nunca se tocam, então basta comparar o primeiro que falta de cada lista.
    private static func combined(_ local: [Edit], _ remote: [Edit]) -> [Edit]? {
        var result: [Edit] = []
        var localIndex = 0
        var remoteIndex = 0
        while localIndex < local.count || remoteIndex < remote.count {
            guard localIndex < local.count else {
                result.append(remote[remoteIndex])
                remoteIndex += 1
                continue
            }
            guard remoteIndex < remote.count else {
                result.append(local[localIndex])
                localIndex += 1
                continue
            }
            let (mine, theirs) = (local[localIndex], remote[remoteIndex])
            if mine.removed.upperBound < theirs.removed.lowerBound {
                result.append(mine)
                localIndex += 1
            } else if theirs.removed.upperBound < mine.removed.lowerBound {
                result.append(theirs)
                remoteIndex += 1
            } else if mine == theirs {
                result.append(mine)
                localIndex += 1
                remoteIndex += 1
            } else {
                return nil
            }
        }
        return result
    }
}
