import AppKit
import MuralKit
import WebKit

/// Decide cada navegação da página do detalhe do link: o que carrega no app e o que o sistema abre fora dele.
///
/// A regra está em `LinkNavigationPolicy`; aqui ela é ligada ao WebKit e ao sistema. Cada navegação também liga o
/// Global Privacy Control e exige HTTPS, sem a exceção de ATS: um `http` que não responde em `https` falha (e vira a
/// tela de erro do detalhe) em vez de cair para `http`.
nonisolated struct LinkNavigationDecider: WebPage.NavigationDeciding {
    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.isGlobalPrivacyControlEnabled = true
        preferences.preferredHTTPSNavigationPolicy = .errorOnFailure

        // Só clique em link e envio de formulário contam como pedido da pessoa; o resto a própria página fez.
        let isUserInitiated = action.navigationType == .linkActivated || action.navigationType == .formSubmitted
        let decision = LinkNavigationPolicy.decide(
            url: action.request.url,
            isMainFrame: action.target?.isMainFrame ?? false,
            opensNewWindow: action.target == nil,
            shouldDownload: action.shouldPerformDownload,
            isUserInitiated: isUserInitiated)
        return carryOut(decision) ? .allow : .cancel
    }

    @MainActor
    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        let decision = LinkNavigationPolicy.decide(canShowMimeType: response.canShowMimeType, url: response.response.url)
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
