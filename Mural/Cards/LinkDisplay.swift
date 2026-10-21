import Foundation
import MuralKit

extension LinkInfo {
    /// Host do endereço como o cartão o mostra: em minúsculas e sem `www.`.
    var displayHost: String { WebLink.displayHost(of: url) }

    /// Nome do site para mostrar: o que a página declara ou, sem ele, o host.
    var displaySiteName: String { siteName ?? displayHost }
}

extension BoardItem {
    /// Endereço a abrir no navegador: o de um cartão de link, desde que seja `http` ou `https`.
    /// Outro esquema (um mural editado à mão, por exemplo) não é entregue ao sistema.
    var browserURL: URL? {
        guard kind == .link, let url = link?.url, WebLink.isWeb(url) else { return nil }
        return url
    }
}
