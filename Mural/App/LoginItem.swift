import Foundation
import Observation
import ServiceManagement

// "Abrir ao Iniciar Sessão": o Mural se registra como item de início de sessão (`SMAppService.mainApp`, que funciona no
// App Sandbox).
//
// A opção começa DESLIGADA. A regra da App Store é que nada abra sozinho no início de sessão sem a pessoa pedir: só o
// gesto dela (`LoginItemModel.setOn(_:)`) registra o app; criar o modelo e atualizá-lo apenas leem o estado. Aberto pelo
// início de sessão, o Mural fica só na barra de menus.

/// O serviço de início de sessão do sistema, reduzido ao que o Mural usa. Existe para os testes trocarem o `SMAppService`
/// de verdade por um falso: registrar o app de verdade mexe nos Ajustes do Sistema de quem roda os testes.
@MainActor
protocol LoginItemService: AnyObject {
    /// O estado do registro. O sistema é a fonte: a pessoa pode mudá-lo nos Ajustes do Sistema a qualquer momento.
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    /// Abre Ajustes do Sistema › Itens de Início de Sessão.
    func openSystemSettings()
}

/// O serviço de verdade: registra o próprio app. Lê `SMAppService.mainApp` a cada uso, sem guardar o objeto, para o estado
/// nunca vir de uma leitura antiga.
@MainActor
final class SystemLoginItem: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// O estado da opção "Abrir ao Iniciar Sessão", compartilhado pelo painel da barra de menus e pelo menu do app.
///
/// Sem SwiftUI, para ser testado sem desenhar nada e com um serviço falso: o de verdade (`SystemLoginItem`) nunca roda em
/// teste.
@MainActor
@Observable
final class LoginItemModel {
    static let shared = LoginItemModel()

    /// O estado do registro na última leitura (`init`, `refresh()` ou uma mudança por `setOn(_:)`).
    private(set) var status: SMAppService.Status
    /// Por que a última mudança falhou; `nil` enquanto nenhuma falhou e depois de uma que deu certo.
    private(set) var errorMessage: String?

    /// Ligada: registrada, com ou sem a permissão da pessoa nos Ajustes do Sistema. Mudar pede ao sistema por
    /// ``setOn(_:)``, e o que se lê depois é o que ele decidiu: um pedido recusado volta sozinho.
    var isOn: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setOn(newValue) }
    }
    /// Registrada, mas a pessoa ainda precisa permitir nos Ajustes do Sistema.
    var needsApproval: Bool { status == .requiresApproval }

    private let service: any LoginItemService

    init(service: any LoginItemService = SystemLoginItem()) {
        self.service = service
        status = service.status
    }

    /// Relê o estado do sistema. Chamado quando o painel aparece, porque a pessoa pode ter mudado a opção nos Ajustes.
    func refresh() {
        status = service.status
    }

    /// Registra (`true`) ou cancela o registro (`false`) do app e relê o estado, que é o que o sistema decidir: ligar pode
    /// deixá-lo à espera da permissão. Se o sistema recusar, guarda o motivo em ``errorMessage``; o estado relido também
    /// vale nesse caso, porque o motivo pode ser um estado que mudou por fora (já registrado, por exemplo).
    func setOn(_ on: Bool) {
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível mudar a abertura ao iniciar sessão: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Leva a pessoa a Ajustes do Sistema › Itens de Início de Sessão, onde ela permite o Mural.
    func openSystemSettings() {
        service.openSystemSettings()
    }
}
