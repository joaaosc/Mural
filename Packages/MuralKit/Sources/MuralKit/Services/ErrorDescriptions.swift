import Foundation

// Frases mostradas na interface. Sem estas descrições, `localizedDescription` exibe
// "The operation couldn’t be completed. (MuralKit.… error 0.)". O detalhe técnico,
// quando ajuda, vai entre parênteses e encurtado.

extension BoardSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .flushInProgress:
            "O mural está sendo salvo. Tente de novo em instantes."
        case .generationMismatch:
            "O mural mudou enquanto a alteração era aplicada. Tente de novo."
        case .retired:
            "Este mural foi fechado nesta janela e não aceita mais alterações."
        }
    }
}

extension BoardRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBoardID:
            "O identificador do mural é inválido."
        case .boardNotFound:
            "O mural não foi encontrado."
        case .corruptedManifest:
            "As informações do mural estão ilegíveis."
        case .corruptedBoard:
            "O conteúdo do mural está ilegível."
        case .futureManifestSchema(let version):
            "Este mural foi salvo por uma versão mais nova do Mural (formato \(version))."
        case .futureBoardFormat(let version):
            "Este mural foi salvo por uma versão mais nova do Mural (formato \(version)). Nada foi alterado."
        case .futureWorkspaceSchema(let version):
            "O estado visual deste mural vem de uma versão mais nova do Mural (formato \(version))."
        case .staleRevision:
            "Uma versão mais nova deste mural já foi salva; a alteração antiga foi descartada."
        case .conflictingRevision:
            "Duas versões diferentes do mural tentaram ser salvas ao mesmo tempo; nada foi sobrescrito."
        case .identityMismatch:
            "Os arquivos encontrados pertencem a outro mural."
        case .injectedFailure(let point):
            "Falha simulada (\(point.rawValue))."
        case .missingAsset(let name):
            "Um arquivo de mídia do mural está faltando (\(name))."
        case .io(let detail):
            "Não foi possível ler ou gravar os arquivos do mural (\(ErrorDetail.short(detail)))."
        }
    }
}

extension BoardLibraryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .futureSchema(let version):
            "A biblioteca foi salva por uma versão mais nova do Mural (formato \(version))."
        case .unavailableRoute:
            "Este mural não está mais disponível. Ele pode ter sido renomeado, promovido ou apagado."
        case .invalidPackage(let url):
            "O mural “\(url.deletingPathExtension().lastPathComponent)” está incompleto ou danificado."
        case .corruptedLibraryState:
            "O estado da biblioteca de murais está ilegível."
        case .migrationRequiredButUnavailable:
            "Não foi possível migrar o mural antigo."
        case .injectedFailure(let point):
            "Falha simulada (\(point.rawValue))."
        case .portable(let error):
            error.errorDescription
        case .io(let detail):
            "Não foi possível ler ou gravar a biblioteca de murais (\(ErrorDetail.short(detail)))."
        }
    }
}

extension BoardPortablePackageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .packageNotDirectory:
            "O arquivo escolhido não é um pacote de mural."
        case .unexpectedEntry(let name):
            "O pacote contém um item inesperado (\(name))."
        case .symlink:
            "O pacote contém um atalho (link simbólico), o que não é permitido."
        case .nestedDirectory:
            "O pacote contém pastas dentro de Items, o que não é permitido."
        case .fileTooLarge(let url, let limit):
            "O arquivo \(url.lastPathComponent) é grande demais (limite de \(ErrorDetail.bytes(limit)))."
        case .packageTooLarge(let limit):
            "O pacote é grande demais (limite de \(ErrorDetail.bytes(limit)))."
        case .invalidManifest:
            "As informações do pacote estão ilegíveis."
        case .futureManifestSchema(let version), .futureBoardSchema(let version),
            .futureWorkspaceSchema(let version):
            "O pacote foi criado por uma versão mais nova do Mural (formato \(version))."
        case .invalidBoard:
            "O conteúdo do pacote está ilegível."
        case .tooManyItems(let limit):
            "O pacote tem cartões demais (limite de \(limit))."
        case .duplicateItemID:
            "O pacote tem cartões repetidos."
        case .invalidItemParent:
            "O pacote tem um cartão dentro de uma pasta que não existe."
        case .invalidItemPosition:
            "O pacote tem um cartão com posição inválida."
        case .invalidFileName:
            "O pacote tem um nome de arquivo inválido."
        case .invalidReminder:
            "O pacote tem um cartão de lembrete inválido."
        case .missingAsset(let name):
            "Falta um arquivo de mídia no pacote (\(name))."
        case .duplicateAsset(let name):
            "Dois cartões do pacote usam o mesmo arquivo (\(name))."
        case .unreferencedAsset(let name):
            "O pacote tem um arquivo que nenhum cartão usa (\(name))."
        case .assetKindMismatch:
            "O tipo de um arquivo do pacote não combina com o cartão."
        case .notDescendant:
            "O caminho escolhido está fora da área permitida."
        case .destinationExists:
            "Já existe um item nesse destino."
        case .io(let detail):
            "Não foi possível ler ou gravar o pacote (\(ErrorDetail.short(detail)))."
        }
    }
}

enum ErrorDetail {
    /// Mantém só o começo de descrições longas de erros do sistema.
    static func short(_ detail: String, limit: Int = 120) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}
