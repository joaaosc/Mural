import Foundation
import Security

/// Se esta cópia do app pode falar com o iCloud.
///
/// Sem o entitlement de CloudKit nada pode criar um `CKContainer`: criá-lo encerra o app. Por isso quem monta a sincronização
/// confere aqui antes de tocar no CloudKit. Hoje o app NÃO tem o entitlement (a Fase 0, com a conta de desenvolvedor, ainda está
/// pendente), então em uso comum a sincronização fica desligada.
nonisolated enum CloudAvailability {
    /// A chave do entitlement com os serviços do iCloud que o app usa.
    static let servicesEntitlement = "com.apple.developer.icloud-services"

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

    /// O valor do entitlement de serviços do iCloud neste processo; `nil` sem ele.
    private static var servicesValue: Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, servicesEntitlement as CFString, nil)
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
}
