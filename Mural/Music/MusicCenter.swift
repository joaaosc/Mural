/// Escolhe a ponte com o Apple Music: a falsa nos testes de interface, a do MusicKit no uso normal.
@MainActor
enum MusicCenter {
    static let shared: any MusicProviding =
        LaunchConfiguration.isUITesting ? FakeMusic() : MusicKitService()
}
