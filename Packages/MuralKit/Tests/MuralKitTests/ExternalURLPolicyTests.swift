import Foundation
import Testing

@testable import MuralKit

@Suite("Política de endereços externos")
struct ExternalURLPolicyTests {
    @Test(
        "Aceita web e esquemas de sistema",
        arguments: [
            "https://example.com/a", "http://example.com", "mailto:a@b.com", "tel:+5521999999999",
            "sms:+5521999999999", "facetime://a@b.com", "facetime-audio://a@b.com",
        ])
    func allows(_ text: String) throws {
        #expect(ExternalURLPolicy.allowsOpening(try #require(URL(string: text))))
    }

    @Test(
        "Recusa arquivos, atalhos e esquemas de apps",
        arguments: [
            "file:///etc/passwd", "smb://server/share", "shortcuts://run-shortcut?name=x",
            "x-apple.systempreferences:com.apple.preference.security", "javascript:alert(1)",
            "data:text/html,hi", "zoommtg://zoom.us/join?confno=1", "http:///sem-host", "https://",
        ])
    func rejects(_ text: String) throws {
        #expect(!ExternalURLPolicy.allowsOpening(try #require(URL(string: text))))
    }

    @Test(
        "Reconhece links https do Apple Music",
        arguments: [
            "https://music.apple.com/br/album/x/1", "https://MUSIC.apple.com/br/album/x/1",
            "https://itunes.apple.com/br/album/x/1", "https://geo.music.apple.com/br/album/x/1",
        ])
    func appleMusic(_ text: String) throws {
        #expect(ExternalURLPolicy.isAppleMusicWebLink(try #require(URL(string: text))))
    }

    @Test(
        "Recusa links que só parecem do Apple Music",
        arguments: [
            "http://music.apple.com/br/album/x/1", "https://music.apple.com.evil.com/br/album/x/1",
            "https://evil.com/music.apple.com", "https://evil.com@music.apple.com.evil.com/", "mailto:music.apple.com",
        ])
    func notAppleMusic(_ text: String) throws {
        #expect(!ExternalURLPolicy.isAppleMusicWebLink(try #require(URL(string: text))))
    }
}
