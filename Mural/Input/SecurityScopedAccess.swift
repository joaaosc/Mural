import Foundation

/// Abre o acesso de sandbox de URLs vindas do seletor de arquivos durante a importação.
enum SecurityScopedAccess {
    static func withAccess<T>(to urls: [URL], _ body: () -> T) -> T {
        let opened = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in opened { url.stopAccessingSecurityScopedResource() }
        }
        return body()
    }
}
