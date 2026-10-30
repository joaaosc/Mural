import Foundation
import Testing

@testable import MuralKit

@Suite("Política de endereços da rede")
struct NetworkAddressPolicyTests {
    private func isPublic(_ text: String) -> Bool {
        guard let url = URL(string: text) else { return false }
        return NetworkAddressPolicy.isPublicWebAddress(url)
    }

    @Test(
        "Endereços da internet pública passam",
        arguments: [
            "https://example.com/", "http://example.com/x?y=1", "https://sub.exemplo.com.br/a", "https://8.8.8.8/",
            "https://1.1.1.1:8443/", "https://172.32.0.1/", "https://172.15.255.255/", "https://100.63.0.1/",
            "https://100.128.0.1/", "https://169.253.1.1/", "https://[2001:4860:4860::8888]/", "HTTPS://EXAMPLE.COM/",
            "https://musica.apple.com/x", "https://localhostel.com/",
        ])
    func publicAddresses(_ text: String) {
        #expect(isPublic(text))
    }

    @Test(
        "Nomes da rede local e do próprio Mac são recusados",
        arguments: [
            "https://localhost:631/", "http://localhost/", "https://app.localhost/", "http://nas.local/x", "https://impressora.local./",
            "https://servidor.internal/", "https://roteador.lan/", "https://casa.home.arpa/", "https://intranet/", "https://LOCALHOST/",
            "https://localhost./",
        ])
    func localNames(_ text: String) {
        #expect(!isPublic(text))
    }

    @Test(
        "IPv4 privado, local ou reservado é recusado",
        arguments: [
            "https://192.168.0.1/", "http://10.0.0.5", "https://10.255.255.255/", "https://127.0.0.1/", "https://127.1.2.3:8080/",
            "https://0.0.0.0/", "https://0.1.2.3/", "https://169.254.169.254/", "https://172.16.0.1/", "https://172.31.255.255/",
            "https://100.64.0.1/", "https://100.127.255.255/", "https://224.0.0.1/", "https://239.1.1.1/", "https://240.0.0.1/",
            "https://255.255.255.255/",
        ])
    func privateIPv4(_ text: String) {
        #expect(!isPublic(text))
    }

    @Test(
        "IPv6 local, privado, multicast ou mapeado privado é recusado",
        arguments: [
            "https://[::1]/", "https://[::]/", "https://[fe80::1]/", "https://[febf::1]/", "https://[fc00::1]/",
            "https://[fd12:3456::1]/", "https://[ff02::1]/", "https://[::ffff:192.168.0.1]/", "https://[::ffff:127.0.0.1]/",
            "https://[::ffff:10.0.0.1]/", "https://[::ffff:c0a8:1]/", "http://[::1]:8080/",
        ])
    func privateIPv6(_ text: String) {
        #expect(!isPublic(text))
    }

    @Test("IPv6 público e IPv4 mapeado público passam")
    func publicIPv6() {
        #expect(isPublic("https://[2606:4700::1111]/"))
        #expect(isPublic("https://[::ffff:8.8.8.8]/"))
    }

    @Test(
        "Formas numéricas que o sistema converteria em IP são recusadas",
        arguments: ["http://2130706433/", "http://0x7f.1/", "http://127.1/"])
    func numericForms(_ text: String) {
        #expect(!isPublic(text))
    }

    @Test(
        "Esquema que não é http nem https é recusado",
        arguments: ["file:///etc/hosts", "data:text/html,<b>oi</b>", "ftp://example.com/", "javascript:alert(1)", "mailto:a@example.com"])
    func otherSchemes(_ text: String) {
        #expect(!isPublic(text))
    }

    @Test("Sem host é recusado")
    func missingHost() {
        #expect(!isPublic("https:///caminho"))
        #expect(!isPublic("https://"))
    }
}
