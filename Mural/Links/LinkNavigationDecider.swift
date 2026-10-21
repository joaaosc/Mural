import AppKit
import MuralKit
import WebKit

/// Decide cada navegação da página do detalhe do link: o que carrega no app e o que o sistema abre fora dele.
///
/// A regra está em `LinkNavigationPolicy`; aqui ela é ligada ao WebKit e ao sistema. Cada navegação também liga o
/// Global Privacy Control e exige HTTPS, sem a exceção de ATS: um `http` que não responde em `https` falha (e vira a
/// tela de erro do detalhe) em vez de cair para `http`.
///
/// Guarda o endereço da última navegação que a pessoa pediu e ainda espera resposta: só a resposta dela, se o WebKit
/// não souber mostrá-la (um arquivo para baixar), vai para o navegador. Uma página não dispara um download sozinha.
nonisolated final class LinkNavigationDecider: WebPage.NavigationDeciding {
    /// Endereço da última navegação pedida pela pessoa (clique, envio de formulário, abertura do cartão) cuja
    /// resposta ainda não chegou; `nil` quando não há. Um redirecionamento do servidor refaz o pedido com o mesmo
    /// tipo de navegação, então o endereço guardado acompanha a cadeia até a resposta final.
    @MainActor private var userNavigationURL: URL?

    /// Anota uma navegação que o próprio app faz a pedido da pessoa (abrir o cartão, tentar de novo): se o endereço
    /// for um arquivo para baixar, a resposta vai para o navegador, como a de um clique.
    @MainActor
    func noteUserRequest(for url: URL) {
        userNavigationURL = url
    }

    // MARK: Regras

    /// Decide um pedido de navegação a partir de valores simples, os que `decidePolicy(for:preferences:)` tira do WebKit.
    ///
    /// Só clique em link e envio de formulário contam como pedido da pessoa; o resto (redirecionamento por script, por
    /// exemplo) a própria página fez. Um pedido da pessoa que segue na página fica guardado para a resposta.
    @MainActor
    func decide(
        url: URL?, isMainFrame: Bool, opensNewWindow: Bool, shouldDownload: Bool, navigationType: WKNavigationType
    ) -> LinkNavigationPolicy.Decision {
        let isUserInitiated = navigationType == .linkActivated || navigationType == .formSubmitted
        let decision = LinkNavigationPolicy.decide(
            url: url, isMainFrame: isMainFrame, opensNewWindow: opensNewWindow, shouldDownload: shouldDownload,
            isUserInitiated: isUserInitiated)
        // Só quem fica na página espera uma resposta: o que foi aberto fora ou descartado não deixa pedido pendente.
        if isUserInitiated, decision == .allow { userNavigationURL = url }
        return decision
    }

    /// Decide o que fazer com a resposta do servidor. A resposta da navegação que a pessoa pediu vale uma vez só:
    /// se a página pedir o mesmo endereço de novo, por conta própria, a nova resposta já não é da pessoa.
    @MainActor
    func decide(canShowMimeType: Bool, url: URL?) -> LinkNavigationPolicy.Decision {
        let answersUserRequest = LinkNavigationPolicy.isSamePage(url, userNavigationURL)
        if answersUserRequest { userNavigationURL = nil }
        return LinkNavigationPolicy.decide(canShowMimeType: canShowMimeType, url: url, isUserInitiated: answersUserRequest)
    }

    // MARK: WebPage.NavigationDeciding

    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.isGlobalPrivacyControlEnabled = true
        preferences.preferredHTTPSNavigationPolicy = .errorOnFailure

        let decision = decide(
            url: action.request.url,
            isMainFrame: action.target?.isMainFrame ?? false,
            opensNewWindow: action.target == nil,
            shouldDownload: action.shouldPerformDownload,
            navigationType: action.navigationType)
        return carryOut(decision) ? .allow : .cancel
    }

    @MainActor
    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        let decision = decide(canShowMimeType: response.canShowMimeType, url: response.response.url)
        return carryOut(decision) ? .allow : .cancel
    }

    /// Faz fora do app o que a decisão pede e diz se a navegação segue na página.
    @MainActor
    private func carryOut(_ decision: LinkNavigationPolicy.Decision) -> Bool {
        switch decision {
        case .allow:
            return true
        case .cancel:
            return false
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
            return false
        }
    }
}
