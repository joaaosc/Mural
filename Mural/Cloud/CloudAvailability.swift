import Foundation
import Security

/// Em qual ambiente do CloudKit esta cópia do app fala. Cada um tem as suas zonas e os seus registros: o que existe num não existe no
/// outro. A cópia de desenvolvimento (rodada pelo Xcode) usa `Development`; a do TestFlight e a da loja, `Production`.
nonisolated enum CloudEnvironment: String, Sendable {
    case development = "Development"
    case production = "Production"
}

/// Se esta cópia do app pode falar com o iCloud.
///
/// Sem o entitlement de CloudKit nada pode criar um `CKContainer`: criá-lo encerra o app. Por isso quem monta a sincronização
/// confere aqui antes de tocar no CloudKit. Hoje o app NÃO tem o entitlement (a Fase 0, com a conta de desenvolvedor, ainda está
/// pendente), então em uso comum a sincronização fica desligada.
nonisolated enum CloudAvailability {
    /// A chave do entitlement com os serviços do iCloud que o app usa.
    static let servicesEntitlement = "com.apple.developer.icloud-services"

    /// A chave do entitlement com o ambiente do container do iCloud (`Development` ou `Production`). A build de desenvolvimento deste
    /// projeto não a traz; a exportada para a loja traz `Production`.
    static let containerEnvironmentEntitlement = "com.apple.developer.icloud-container-environment"

    /// A chave do entitlement com o ambiente das notificações push (`development` ou `production`), que acompanha o do CloudKit.
    static let apsEnvironmentEntitlement = "com.apple.developer.aps-environment"

    /// O valor `"CloudKit"` que a chave precisa listar.
    static let cloudKitService = "CloudKit"

    /// O valor `"CloudDocuments"` que a chave precisa listar para o app guardar arquivos no iCloud Drive.
    static let cloudDocumentsService = "CloudDocuments"

    /// O processo atual foi assinado com o entitlement de CloudKit.
    static var hasCloudKitEntitlement: Bool {
        listsCloudKit(servicesValue)
    }

    /// O processo atual foi assinado com o entitlement do iCloud Drive (CloudDocuments).
    static var hasCloudDocumentsEntitlement: Bool {
        listsCloudDocuments(servicesValue)
    }

    /// O ambiente do CloudKit em que este processo fala, lido dos entitlements com que foi assinado.
    static var currentEnvironment: CloudEnvironment {
        environment(
            containerEnvironment: entitlementValue(containerEnvironmentEntitlement),
            apsEnvironment: entitlementValue(apsEnvironmentEntitlement))
    }

    /// O valor de um entitlement neste processo; `nil` sem ele.
    private static func entitlementValue(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }

    /// O valor do entitlement de serviços do iCloud neste processo; `nil` sem ele.
    private static var servicesValue: Any? {
        entitlementValue(servicesEntitlement)
    }

    /// O valor do entitlement de serviços do iCloud lista o CloudKit. Separado de `hasCloudKitEntitlement` para os testes
    /// conferirem a leitura sem depender de como o teste foi assinado.
    static func listsCloudKit(_ services: Any?) -> Bool {
        (services as? [String])?.contains(cloudKitService) ?? false
    }

    /// O valor do entitlement de serviços do iCloud lista o CloudDocuments (iCloud Drive).
    static func listsCloudDocuments(_ services: Any?) -> Bool {
        (services as? [String])?.contains(cloudDocumentsService) ?? false
    }

    /// O ambiente que os valores dos entitlements dizem. Separado de `currentEnvironment` para os testes não dependerem de como
    /// foram assinados.
    ///
    /// Vale o do container, quando traz um ambiente conhecido. Sem ele (ou com um valor que não se conhece), vale o das notificações:
    /// `production` é produção, e qualquer outra coisa, inclusive a falta dele, é desenvolvimento.
    static func environment(containerEnvironment: Any?, apsEnvironment: Any?) -> CloudEnvironment {
        if let value = containerEnvironment as? String, let declared = CloudEnvironment(rawValue: value) { return declared }
        return (apsEnvironment as? String) == "production" ? .production : .development
    }
}
