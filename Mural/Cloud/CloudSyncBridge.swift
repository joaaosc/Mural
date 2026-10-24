import Foundation
import MuralKit
import MuralSync
import os

/// A ponte entre o coordenador de sincronização (um actor, fora da tela) e as sessões de janela do app (Main Actor).
///
/// O protocolo `BoardSyncHost` é `Sendable` e as sessões não são: este tipo vive no Main Actor, que o torna `Sendable`, e o
/// coordenador o chama com `await`. Cada método do protocolo leva `@MainActor` explícito: sem isso o compilador trata o método
/// como não isolado e recusa tocar nas sessões.
///
/// Quem guarda a ponte é o coordenador, e ela não guarda o controlador (só um fecho fraco para os avisos): não há ciclo que
/// impeça o controlador de sair da memória.
///
/// Nunca existem duas `BoardWindowSession` do mesmo mural, e nada aqui grava um mural direto pelo `BoardSessionRegistry`: tudo o
/// que muda um mural passa por `BoardDelivery.withSession(for:perform:)`, que escolhe a sessão certa e entra na mesma fila das
/// entregas do painel.
@MainActor
final class CloudSyncBridge: BoardSyncHost {
    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "Sincronização")

    private let scope: CloudDatabaseScope
    private let registry: BoardSessionRegistry
    private let delivery: BoardDelivery
    private let openSessions: OpenBoardSessions
    private let notify: @MainActor (CloudSyncNotice) -> Void

    /// - Parameters:
    ///   - scope: o banco do coordenador que usa esta ponte; vale quando o manifesto do mural não diz o banco.
    ///   - delivery: quem escolhe a sessão do mural e guarda a fila serial; a aba vem de `delivery.tabs`.
    ///   - notify: recebe os avisos para a pessoa.
    init(
        scope: CloudDatabaseScope,
        registry: BoardSessionRegistry,
        delivery: BoardDelivery,
        openSessions: OpenBoardSessions = .shared,
        notify: @escaping @MainActor (CloudSyncNotice) -> Void
    ) {
        self.scope = scope
        self.registry = registry
        self.delivery = delivery
        self.openSessions = openSessions
        self.notify = notify
    }

    // MARK: Mural local

    /// O mural como foi gravado pela última vez, nunca o `model.board` com edições ainda não gravadas (regra 1): o que sobe ao
    /// iCloud já está no disco, e um travamento do app não o desfaz depois.
    ///
    /// Com uma janela do mural aberta (aba ou avulsa) que já tem um mural gravado, vale o dela; senão, o do disco. Uma janela que
    /// abriu com mudanças ainda fora do disco (`lastPersistedBoard == nil`) também cai no disco.
    @MainActor
    func localBoard(_ id: BoardID) async -> LocalBoardSnapshot? {
        if let session = openSessions.live.first(where: { $0.boardID == id && !$0.isClosed && $0.lastPersistedBoard != nil }),
            let board = session.lastPersistedBoard, let domainSession = session.domainSession
        {
            // O mural e o nome são lidos antes de qualquer espera: a sessão pode gravar de novo durante ela.
            let name = session.manifestName
            let package = await domainSession.repository.packageURL(for: id)
            return LocalBoardSnapshot(name: name, board: board, itemsDirectory: BoardStore(directory: package).itemsDirectory)
        }

        let route = BoardRoute.saved(id)
        let library = registry.library
        do {
            guard let snapshot = try await library.open(route) else { return nil }
            let package = try await library.repository(for: route).packageURL(for: id)
            return LocalBoardSnapshot(
                name: snapshot.manifest.name, board: snapshot.board, itemsDirectory: BoardStore(directory: package).itemsDirectory)
        } catch {
            Self.log.error(
                "Mural \(id.rawValue.uuidString, privacy: .public) não lido do disco: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Receber

    /// Põe os arquivos que chegaram em `Items/` e entrega o resto à sessão de janela do mural, que junta e grava antes de voltar
    /// (regra 2). Os arquivos vão primeiro: o cartão que chegou apareceria sem a mídia se a ordem fosse a outra.
    ///
    /// Qualquer falha (mural que não abre, arquivo que não copia, gravação que não passa) é lançada: o coordenador mantém o estado
    /// antigo e marca o mural para uma busca completa.
    @MainActor
    func applyRemote(_ id: BoardID, received: ReceivedChanges) async throws {
        try await delivery.withSession(for: .saved(id)) { [self] session, _ in
            try await copyFiles(received.files, into: session)
            try await session.applyRemote(received)
        }
    }

    /// Copia para `Items/` do mural cada arquivo que ainda não está lá. Um nome que já existe tem o mesmo conteúdo (o nome vem do
    /// conteúdo), então não é sobrescrito. A cópia vai para um nome provisório e depois é renomeada: uma queda no meio não deixa
    /// um arquivo pela metade com o nome final, que nunca seria refeito.
    private func copyFiles(_ files: [String: URL], into session: BoardWindowSession) async throws {
        guard !files.isEmpty else { return }
        guard let domainSession = session.domainSession else { throw BoardSyncApplyError.unavailable }
        let package = await domainSession.repository.packageURL(for: session.boardID)
        let items = BoardStore(directory: package).itemsDirectory
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: items, withIntermediateDirectories: true)
            for (name, source) in files.sorted(by: { $0.key < $1.key }) {
                // O domínio já recusa nome inseguro; conferir de novo custa pouco e impede sair de `Items/`.
                guard BoardRepository.isSafeAssetName(name) else { continue }
                let destination = items.appendingPathComponent(name, isDirectory: false)
                guard !manager.fileExists(atPath: destination.path) else { continue }
                let partial = items.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: false)
                do {
                    try manager.copyItem(at: source, to: partial)
                    try manager.moveItem(at: partial, to: destination)
                } catch {
                    try? manager.removeItem(at: partial)
                    throw error
                }
            }
        } catch {
            throw BoardSyncApplyError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: Mural removido

    /// O mural deixou de existir no iCloud para este Mac. Cada mudança no mural passa pela fila serial das entregas (o pacote que
    /// sai, em `serially`; o `cloud` que sai, em `withSession`), para não correr junto com uma junção ou uma colagem no mesmo
    /// mural. A leitura do manifesto, que só decide o que fazer, fica fora dela: `withSession` já usa a fila, e entrar nela de
    /// dentro dela travaria.
    ///
    /// O coordenador já parou de acompanhar o mural e apagou o estado dele antes de chamar (`remove`), e chama dentro da sua trava
    /// de eventos: pedir `stopTracking` daqui esperaria essa trava e travaria os dois. Por isso não há `stopTracking` aqui.
    @MainActor
    func boardRemoved(_ id: BoardID, reason: BoardRemovalReason) async {
        await handleRemoval(of: id, reason: reason)
    }

    /// O banco vem do manifesto; sem ele (mural ilegível ou já sem `cloud`), vale o banco do coordenador que avisou.
    ///
    /// - Mural de outra pessoa (banco compartilhado), ou do banco privado com `.zoneDeleted` (ela o apagou ou parou de
    ///   compartilhá-lo em outro Mac): o pacote sai, pelo caminho de "Excluir Mural" (vai para o Lixo, e a aba fecha).
    /// - Banco privado com `.accountChanged`, `.cloudDataErased` ou `.accessRevoked`: só a cópia na nuvem sumiu. O pacote fica e o
    ///   mural volta a ser só deste Mac; apagá-lo perderia o conteúdo da pessoa.
    private func handleRemoval(of id: BoardID, reason: BoardRemovalReason) async {
        let route = BoardRoute.saved(id)
        let snapshot = try? await registry.library.open(route)
        let database = snapshot?.manifest.cloud?.database ?? BoardCloudInfo.Database(rawValue: scope.rawValue) ?? .private
        let name = snapshot?.manifest.name ?? "Mural"
        if database == .private, reason != .zoneDeleted {
            await keepLocally(id, name: name)
        } else {
            await delivery.serially { [self] in await removePackage(id, name: name, database: database) }
        }
    }

    /// Fecha a aba (se aberta) e manda o pacote para o Lixo, como a exclusão feita pela pessoa.
    private func removePackage(_ id: BoardID, name: String, database: BoardCloudInfo.Database) async {
        let route = BoardRoute.saved(id)
        do {
            if let tabs = delivery.tabs {
                try await tabs.deleteBoard(route)
            } else {
                await registry.close(id)
                try await registry.library.deleteBoard(route)
            }
        } catch BoardLibraryError.unavailableRoute {
            // Já não há pacote neste Mac: não há o que apagar nem o que avisar.
            return
        } catch {
            Self.log.error("Mural removido não apagado: \(String(describing: error), privacy: .public)")
            notify(
                CloudSyncNotice(boardID: id, message: "O mural “\(name)” deixou de existir no iCloud, mas não pôde ser removido deste Mac.")
            )
            return
        }
        let message =
            database == .shared
            ? "Você não tem mais acesso ao mural “\(name)”. Ele foi movido para o Lixo."
            : "O mural “\(name)” foi apagado do iCloud em outro Mac. Ele foi movido para o Lixo."
        notify(CloudSyncNotice(boardID: id, message: message))
    }

    /// Tira o `cloud` do manifesto e avisa a pessoa. Com uma janela do mural aberta (aba, aba fechando ou sessão avulsa), pela
    /// própria sessão (`setCloud`, que também desliga o modo só leitura): gravar pela biblioteca por baixo dela faria a próxima
    /// gravação da sessão devolver o `cloud` ao disco. Sem janela, pela biblioteca.
    private func keepLocally(_ id: BoardID, name: String) async {
        let route = BoardRoute.saved(id)
        do {
            if openSessions.live.contains(where: { $0.boardID == id && !$0.isClosed }) {
                try await delivery.withSession(for: route) { session, _ in try await session.setCloud(nil) }
            } else {
                guard try await clearCloudOnDisk(id) else { return }
            }
            notify(
                CloudSyncNotice(
                    boardID: id,
                    message: "O mural “\(name)” voltou a ser só deste Mac: a cópia dele no iCloud não está mais disponível."))
        } catch {
            Self.log.error("Mural não voltou a ser local: \(String(describing: error), privacy: .public)")
            notify(
                CloudSyncNotice(
                    boardID: id, message: "O mural “\(name)” perdeu a cópia no iCloud, mas continua marcado como sincronizado."))
        }
    }

    /// Tira o `cloud` do manifesto pela biblioteca, para o mural sem janela. Se uma gravação de outra janela passar na frente
    /// (revisão velha), lê de novo e tenta uma vez mais.
    /// - Returns: `false` se o mural já não existe.
    private func clearCloudOnDisk(_ id: BoardID) async throws -> Bool {
        let route = BoardRoute.saved(id)
        for attempt in 1...2 {
            do {
                guard var snapshot = try await registry.library.open(route) else { return false }
                if snapshot.manifest.cloud != nil {
                    snapshot.manifest.cloud = nil
                    try await registry.library.repository(for: route).save(snapshot)
                }
                return true
            } catch BoardRepositoryError.staleRevision where attempt == 1 {
                continue
            }
        }
        return false
    }
}
