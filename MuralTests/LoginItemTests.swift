import Foundation
import ServiceManagement
import Testing

@testable import Mural

/// O serviço de início de sessão de mentira: guarda o estado, conta as chamadas e falha quando o teste manda. O de verdade
/// (`SystemLoginItem`) registraria o app nos Ajustes do Sistema de quem roda os testes e nunca entra aqui.
@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    /// O estado depois de um `register()` que deu certo: `.enabled`, ou `.requiresApproval` quando a pessoa ainda precisa
    /// permitir nos Ajustes do Sistema.
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var settingsOpened = 0

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        settingsOpened += 1
    }
}

private struct FakeLoginItemError: LocalizedError {
    var errorDescription: String? { "falha do teste" }
}

/// A opção "Abrir ao Iniciar Sessão": o que o modelo faz com o serviço do sistema, sempre um falso.
@Suite("Abrir ao Iniciar Sessão")
@MainActor
struct LoginItemTests {
    private static let failureMessage = "Não foi possível mudar a abertura ao iniciar sessão: falha do teste"

    // MARK: Estado inicial

    @Test("Um modelo novo começa com o estado do serviço, desligado por padrão, e não registra nada")
    func startsFromServiceState() {
        let service = FakeLoginItemService()

        let model = LoginItemModel(service: service)

        #expect(model.status == .notRegistered)
        #expect(!model.isOn)
        #expect(!model.needsApproval)
        #expect(model.errorMessage == nil)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }

    @Test("Um modelo novo mostra como ligado o que o serviço já tem registrado")
    func startsOnWhenServiceIsRegistered() {
        let model = LoginItemModel(service: FakeLoginItemService(status: .enabled))

        #expect(model.status == .enabled)
        #expect(model.isOn)
    }

    @Test(
        "Só habilitado e à espera de permissão contam como ligado; só o segundo pede a permissão",
        arguments: [
            (SMAppService.Status.notRegistered, false, false),
            (SMAppService.Status.enabled, true, false),
            (SMAppService.Status.requiresApproval, true, true),
            (SMAppService.Status.notFound, false, false),
        ])
    func mapsStatusToToggle(status: SMAppService.Status, isOn: Bool, needsApproval: Bool) {
        let model = LoginItemModel(service: FakeLoginItemService(status: status))

        #expect(model.isOn == isOn)
        #expect(model.needsApproval == needsApproval)
    }

    // MARK: Ligar e desligar

    @Test("Ligar registra o app e o estado fica habilitado")
    func turningOnRegisters() {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)

        model.setOn(true)

        #expect(service.registerCalls == 1)
        #expect(service.unregisterCalls == 0)
        #expect(model.status == .enabled)
        #expect(model.isOn)
        #expect(!model.needsApproval)
        #expect(model.errorMessage == nil)
    }

    @Test("Desligar cancela o registro do app")
    func turningOffUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        let model = LoginItemModel(service: service)

        model.setOn(false)

        #expect(service.unregisterCalls == 1)
        #expect(service.registerCalls == 0)
        #expect(model.status == .notRegistered)
        #expect(!model.isOn)
        #expect(model.errorMessage == nil)
    }

    // MARK: Permissão nos Ajustes

    @Test("À espera de permissão conta como ligado, pede a permissão e leva aos Ajustes do Sistema")
    func requiresApprovalCountsAsOn() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let model = LoginItemModel(service: service)

        #expect(model.isOn)
        #expect(model.needsApproval)

        model.openSystemSettings()

        #expect(service.settingsOpened == 1)
    }

    @Test("Ligar sem a permissão da pessoa deixa o estado à espera dela, sem erro")
    func turningOnCanWaitForApproval() {
        let service = FakeLoginItemService()
        service.statusAfterRegister = .requiresApproval
        let model = LoginItemModel(service: service)

        model.setOn(true)

        #expect(model.status == .requiresApproval)
        #expect(model.isOn)
        #expect(model.needsApproval)
        #expect(model.errorMessage == nil)
    }

    // MARK: Erros

    @Test("Erro ao registrar preenche a mensagem e não muda o estado")
    func registerFailureKeepsState() {
        let service = FakeLoginItemService()
        service.registerError = FakeLoginItemError()
        let model = LoginItemModel(service: service)

        model.setOn(true)

        #expect(service.registerCalls == 1)
        #expect(model.errorMessage == Self.failureMessage)
        #expect(model.status == .notRegistered)
        #expect(!model.isOn)
    }

    @Test("Erro ao cancelar o registro preenche a mensagem e deixa o app ligado")
    func unregisterFailureKeepsState() {
        let service = FakeLoginItemService(status: .enabled)
        service.unregisterError = FakeLoginItemError()
        let model = LoginItemModel(service: service)

        model.setOn(false)

        #expect(service.unregisterCalls == 1)
        #expect(model.errorMessage == Self.failureMessage)
        #expect(model.status == .enabled)
        #expect(model.isOn)
    }

    @Test("Depois de um erro o estado é relido: o sistema pode ter mudado por fora")
    func failureRereadsServiceState() {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)
        // A pessoa ligou nos Ajustes do Sistema; o registro de novo é recusado (já registrado).
        service.status = .enabled
        service.registerError = FakeLoginItemError()

        model.setOn(true)

        #expect(model.errorMessage == Self.failureMessage)
        #expect(model.status == .enabled)
    }

    @Test("Uma mudança que dá certo apaga a mensagem de erro anterior")
    func successClearsPreviousError() {
        let service = FakeLoginItemService()
        service.registerError = FakeLoginItemError()
        let model = LoginItemModel(service: service)
        model.setOn(true)
        #expect(model.errorMessage != nil)

        service.registerError = nil
        model.setOn(true)

        #expect(model.errorMessage == nil)
        #expect(model.status == .enabled)
    }

    // MARK: Atualizar

    @Test("Atualizar relê o estado do serviço, que a pessoa muda nos Ajustes do Sistema")
    func refreshReadsServiceState() {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)

        service.status = .enabled
        #expect(model.status == .notRegistered)

        model.refresh()

        #expect(model.status == .enabled)
        #expect(model.isOn)

        service.status = .notRegistered
        model.refresh()

        #expect(model.status == .notRegistered)
        #expect(!model.isOn)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }
}
