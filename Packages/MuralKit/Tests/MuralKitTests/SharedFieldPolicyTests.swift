import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

private let noteText = "A visita é na segunda. Medir a parede norte.\n\nUma frase só."

private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// Um link com todos os campos preenchidos, as partes locais inclusive.
private func fullLink() -> LinkInfo {
    LinkInfo(
        url: URL(string: "https://apple.com/mac")!, pageTitle: "Mac", siteName: "Apple", summary: "Resumo da página",
        remoteImageURL: URL(string: "https://cdn.example.com/capa.jpg")!, previewImageFile: "A1B2.jpg", iconFile: "C3D4.png",
        preview: .ready(fetchedAt: date(1_000)))
}

/// Uma música com todos os campos preenchidos, as partes locais inclusive.
private func fullMusic() -> MusicSnapshot {
    MusicSnapshot(
        kind: .song, catalogID: "123", storefront: "br", libraryPlaylistName: "Minha", libraryID: "L1",
        url: URL(string: "https://music.apple.com/br/song/123"), title: "Faixa", subtitle: "Artista", albumTitle: "Álbum",
        artworkTemplate: "https://exemplo.test/{w}x{h}.{f}", artworkFile: "capa.jpg", backgroundHex: "#f1e9dd",
        primaryTextHex: "#020201", secondaryTextHex: "#232321", trackCount: 3, releaseDate: "2026-01-02", duration: 12.5)
}

/// Frases curtas que valem para `source`.
private func record(for source: String) -> KeySentenceRecord {
    KeySentenceRecord(source: source, choices: [:])
}

/// Um cartão com as três partes locais preenchidas (frases, link e música), as frases valendo para o texto.
private func fullItem() -> BoardItem {
    BoardItem(
        kind: .text, title: "Completo", createdAt: date(1), text: noteText, keySentences: record(for: noteText), link: fullLink(),
        music: fullMusic())
}

private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// As chaves cujo valor difere entre dois objetos JSON (ou que só existem em um).
private func differingKeys(_ lhs: [String: Any], _ rhs: [String: Any]) -> Set<String> {
    Set(lhs.keys).union(rhs.keys).filter { key in
        (lhs[key] as? NSObject)?.isEqual(rhs[key]) != true
    }
}

// MARK: Escopo

@Suite("Política dos campos compartilhados: escopo")
struct SharedFieldScopeTests {
    @Test("Só as frases curtas são locais; todos os outros campos são compartilhados")
    func scopeOfEveryField() {
        for field in BoardItem.Field.allCases {
            let expected: SharedFieldPolicy.Scope = field == .keySentences ? .local : .shared
            #expect(SharedFieldPolicy.scope(of: field) == expected, "\(field.rawValue)")
        }
    }

    @Test("Só lembrete e música são mantidos por quem criou o cartão")
    func creatorMaintainedKinds() {
        #expect(SharedFieldPolicy.creatorMaintainedKinds == [.reminder, .music])
    }

    @Test("As chaves de um link e de uma música cheios são a união das compartilhadas e das locais, sem repetir nenhuma")
    func keySetsCoverTheTypes() throws {
        let linkKeys = Set(try jsonObject(fullLink()).keys)
        #expect(linkKeys == SharedFieldPolicy.sharedLinkKeys.union(SharedFieldPolicy.localLinkKeys))
        #expect(SharedFieldPolicy.sharedLinkKeys.isDisjoint(with: SharedFieldPolicy.localLinkKeys))

        let musicKeys = Set(try jsonObject(fullMusic()).keys)
        #expect(musicKeys == SharedFieldPolicy.sharedMusicKeys.union(SharedFieldPolicy.localMusicKeys))
        #expect(SharedFieldPolicy.sharedMusicKeys.isDisjoint(with: SharedFieldPolicy.localMusicKeys))
    }

    @Test("As partes locais são as chaves de arquivo e de estado local")
    func localKeysAreTheDeclaredOnes() {
        #expect(SharedFieldPolicy.localLinkKeys == ["previewImageFile", "iconFile", "preview"])
        #expect(SharedFieldPolicy.localMusicKeys == ["artworkFile", "libraryID"])
    }
}

// MARK: shared

@Suite("Política dos campos compartilhados: cópia sem as partes locais")
struct SharedCopyTests {
    @Test("shared tira exatamente as partes locais e mais nada")
    func sharedRemovesOnlyTheLocalParts() {
        let item = fullItem()
        var expected = item
        expected.keySentences = nil
        expected.link?.previewImageFile = nil
        expected.link?.iconFile = nil
        expected.link?.preview = .pending
        expected.music?.artworkFile = nil
        expected.music?.libraryID = nil

        let shared = SharedFieldPolicy.shared(item)
        #expect(shared == expected)
        #expect(SharedFieldPolicy.shared(shared) == shared, "tirar de novo não muda nada")
    }

    @Test("As chaves do JSON que shared altera são exatamente as declaradas como locais")
    func sharedChangesExactlyTheDeclaredKeys() throws {
        let item = fullItem()
        let before = try jsonObject(item)
        let after = try jsonObject(SharedFieldPolicy.shared(item))

        let localFields = Set(BoardItem.Field.allCases.filter { SharedFieldPolicy.scope(of: $0) == .local }.map(\.rawValue))
        // link e música mudam por dentro; só o que é local por inteiro (as frases) some do cartão.
        #expect(differingKeys(before, after) == localFields.union(["link", "music"]))
        #expect(after["keySentences"] == nil)
        #expect(
            differingKeys(try #require(before["link"] as? [String: Any]), try #require(after["link"] as? [String: Any]))
                == SharedFieldPolicy.localLinkKeys)
        #expect(
            differingKeys(try #require(before["music"] as? [String: Any]), try #require(after["music"] as? [String: Any]))
                == SharedFieldPolicy.localMusicKeys)
    }

    @Test("Cartão sem partes locais sai igual")
    func itemWithoutLocalPartsIsUntouched() {
        let folder = BoardItem(kind: .folder, title: "Pasta", tag: "CLIENT 001")
        let sticky = BoardItem(kind: .sticky, title: "Ideia", text: "Oi", stickyColor: .pink, colorTag: .red)
        let pending = BoardItem(kind: .link, title: "swift.org", link: LinkInfo(url: URL(string: "https://swift.org")!))
        for item in [folder, sticky, pending] {
            #expect(SharedFieldPolicy.shared(item) == item)
        }
    }
}

// MARK: preservingLocalFields

@Suite("Política dos campos compartilhados: partes locais de quem já tinha o cartão")
struct PreservingLocalFieldsTests {
    private func preserved(_ local: BoardItem?, in incoming: BoardItem) -> BoardItem {
        SharedFieldPolicy.preservingLocalFields(of: local, in: incoming)
    }

    // MARK: Link

    @Test("Link com o mesmo endereço mantém os arquivos e o estado da prévia deste Mac, e o resto vem de quem chegou")
    func sameURLKeepsThePreview() {
        let local = BoardItem(kind: .link, title: "Apple", link: fullLink())
        var incoming = SharedFieldPolicy.shared(local)
        incoming.title = "Apple Mac"
        incoming.link?.pageTitle = "Mac mini"

        var expected = local
        expected.title = "Apple Mac"
        expected.link?.pageTitle = "Mac mini"
        #expect(preserved(local, in: incoming) == expected)
    }

    @Test("Link com outro endereço descarta os arquivos e o estado da prévia deste Mac")
    func differentURLDropsThePreview() throws {
        let local = BoardItem(kind: .link, title: "Apple", link: fullLink())
        var incoming = SharedFieldPolicy.shared(local)
        incoming.link?.url = try #require(URL(string: "https://swift.org"))

        let merged = preserved(local, in: incoming)
        #expect(merged == incoming)
        #expect(merged.link?.previewImageFile == nil && merged.link?.iconFile == nil)
        #expect(merged.link?.preview == .pending)
    }

    @Test("Os arquivos e o estado de uma prévia que chegaram de fora não valem: só os deste Mac")
    func incomingPreviewPartsAreNeverTrusted() {
        let remote = BoardItem(kind: .link, title: "Apple", link: fullLink())
        // Sem cartão local, ou com um que não tem link, o que veio nas partes locais é descartado.
        #expect(preserved(nil, in: remote) == SharedFieldPolicy.shared(remote))
        #expect(preserved(BoardItem(kind: .sticky, title: "Outro"), in: remote) == SharedFieldPolicy.shared(remote))

        // Com link local do mesmo endereço, valem os do Mac, não os que vieram.
        var local = BoardItem(kind: .link, title: "Apple", link: LinkInfo(url: fullLink().url, previewImageFile: "LOCAL.jpg"))
        local.link?.preview = .failed(at: date(5), attempts: 2)
        let merged = preserved(local, in: remote)
        #expect(merged.link?.previewImageFile == "LOCAL.jpg")
        #expect(merged.link?.iconFile == nil)
        #expect(merged.link?.preview == .failed(at: date(5), attempts: 2))
        #expect(merged.link?.pageTitle == "Mac")
    }

    // MARK: Frases curtas

    @Test("As frases curtas voltam só se o registro ainda vale para o texto que chegou")
    func keySentencesOnlyWhenTheyStillApply() {
        let saved = record(for: noteText)
        let local = BoardItem(kind: .text, title: "Nota", text: noteText, keySentences: saved)
        let incoming = SharedFieldPolicy.shared(local)
        #expect(preserved(local, in: incoming).keySentences == saved)

        // O texto mudou em outro Mac: o registro velho não vale mais.
        var edited = incoming
        edited.text = noteText + " Mais uma frase."
        #expect(preserved(local, in: edited).keySentences == nil)
        #expect(preserved(local, in: edited) == edited)
    }

    @Test("Registro de frases que o cartão local nunca teve, ou que já era de outro texto, não volta")
    func keySentencesNeedAValidLocalRecord() {
        let incoming = BoardItem(kind: .text, title: "Nota", text: noteText)
        #expect(preserved(nil, in: incoming).keySentences == nil)
        #expect(preserved(incoming, in: incoming).keySentences == nil)

        let stale = BoardItem(kind: .text, title: "Nota", text: noteText, keySentences: record(for: "Texto de antes. Com duas frases."))
        #expect(preserved(stale, in: incoming).keySentences == nil)

        // Frases que vieram no cartão de fora também não ficam.
        var foreign = incoming
        foreign.keySentences = record(for: noteText)
        #expect(preserved(nil, in: foreign).keySentences == nil)
        #expect(preserved(stale, in: foreign).keySentences == nil)
    }

    @Test("Na lista, as frases valem para o texto de abertura; em cartão que não dobra, não voltam")
    func keySentencesFollowTheFoldableText() {
        let intro = "Abre a lista. Fecha a lista."
        let list = BoardItem(
            kind: .checklist, title: "Lista", checklist: ChecklistDocument(title: "Lista", intro: intro, sections: []),
            keySentences: record(for: intro))
        #expect(preserved(list, in: SharedFieldPolicy.shared(list)) == list)

        var otherIntro = SharedFieldPolicy.shared(list)
        otherIntro.checklist?.intro = "Outra abertura. Com outra frase."
        #expect(preserved(list, in: otherIntro).keySentences == nil)

        // Post-it não dobra: não há texto que as frases possam valer.
        let sticky = BoardItem(kind: .sticky, title: "Ideia", text: noteText, keySentences: record(for: noteText))
        #expect(preserved(sticky, in: SharedFieldPolicy.shared(sticky)).keySentences == nil)
    }

    // MARK: Música

    @Test("Música igual mantém a capa e o id da biblioteca deste Mac")
    func sameMusicKeepsTheLocalParts() {
        let local = BoardItem(kind: .music, title: "Faixa", music: fullMusic())
        var incoming = SharedFieldPolicy.shared(local)
        incoming.music?.title = "Faixa (remasterizada)"
        incoming.music?.trackCount = 12

        let merged = preserved(local, in: incoming)
        #expect(merged.music?.artworkFile == "capa.jpg")
        #expect(merged.music?.libraryID == "L1")
        #expect(merged.music?.title == "Faixa (remasterizada)")
        #expect(merged.music?.trackCount == 12)
        var expected = local
        expected.music = incoming.music
        expected.music?.artworkFile = "capa.jpg"
        expected.music?.libraryID = "L1"
        #expect(merged == expected)
    }

    @Test("Outra música (tipo, catálogo ou nome da playlist diferentes) não herda a capa nem o id da biblioteca")
    func anotherMusicDropsTheLocalParts() throws {
        let local = BoardItem(kind: .music, title: "Faixa", music: fullMusic())
        let base = SharedFieldPolicy.shared(local)
        let baseMusic = try #require(base.music)
        let variations: [(name: String, edit: (inout MusicSnapshot) -> Void)] = [
            ("tipo", { $0.kind = .album }),
            ("catálogo", { $0.catalogID = "999" }),
            ("sem catálogo", { $0.catalogID = nil }),
            ("nome da playlist", { $0.libraryPlaylistName = "Outra" }),
            ("sem nome da playlist", { $0.libraryPlaylistName = nil }),
        ]
        for variation in variations {
            var music = baseMusic
            variation.edit(&music)
            var incoming = base
            incoming.music = music
            let merged = preserved(local, in: incoming)
            #expect(merged == incoming, "\(variation.name)")
            #expect(merged.music?.artworkFile == nil && merged.music?.libraryID == nil, "\(variation.name)")
        }
    }

    @Test("Os campos que não definem o item (título, capa em molde) mudam sem perder a capa deste Mac")
    func nonIdentifyingFieldsKeepTheLocalParts() {
        let local = BoardItem(kind: .music, title: "Faixa", music: fullMusic())
        var incoming = SharedFieldPolicy.shared(local)
        incoming.music?.title = "Outro título"
        incoming.music?.artworkTemplate = "https://exemplo.test/novo/{w}x{h}.{f}"
        incoming.music?.storefront = "us"
        let merged = preserved(local, in: incoming)
        #expect(merged.music?.artworkFile == "capa.jpg" && merged.music?.libraryID == "L1")
    }

    @Test("Playlist própria sem catálogo é o mesmo item enquanto o nome for o mesmo")
    func libraryPlaylistIsTheSameByName() {
        let playlist = MusicSnapshot(
            kind: .playlist, libraryPlaylistName: "Minha Lista", libraryID: "P7", title: "Minha Lista", artworkFile: "lista.jpg")
        let local = BoardItem(kind: .music, title: "Minha Lista", music: playlist)
        let merged = preserved(local, in: SharedFieldPolicy.shared(local))
        #expect(merged == local)
    }

    // MARK: Conjunto

    @Test("Tirar as partes locais e devolvê-las ao mesmo cartão o deixa como era")
    func removingAndRestoringIsTheIdentity() {
        let intro = "Abre a lista. Fecha a lista."
        let items = [
            fullItem(),
            BoardItem(kind: .text, title: "Nota", text: noteText, keySentences: record(for: noteText)),
            BoardItem(
                kind: .checklist, title: "Lista", checklist: ChecklistDocument(title: "Lista", intro: intro, sections: []),
                keySentences: record(for: intro)),
            BoardItem(kind: .link, title: "Apple", link: fullLink()),
            BoardItem(kind: .music, title: "Faixa", music: fullMusic()),
            BoardItem(kind: .sticky, title: "Ideia", text: "Oi", stickyColor: .blue),
            BoardItem(kind: .folder, title: "Pasta"),
        ]
        for item in items {
            #expect(preserved(item, in: SharedFieldPolicy.shared(item)) == item, "\(item.kind)")
        }
    }

    @Test("Frases que já não valem para o texto do cartão não voltam, e o resto volta")
    func staleSentencesAreTheOnlyThingNotRestored() {
        var item = fullItem()
        item.keySentences = record(for: "Texto de antes. Com duas frases.")
        var expected = item
        expected.keySentences = nil
        #expect(preserved(item, in: SharedFieldPolicy.shared(item)) == expected)
    }

    @Test("Os campos compartilhados do resultado são sempre os de quem chegou")
    func sharedFieldsAlwaysComeFromTheIncomingItem() {
        let local = fullItem()
        var incoming = SharedFieldPolicy.shared(local)
        incoming.title = "Título de outro Mac"
        incoming.text = noteText + " Mais uma frase."
        incoming.position = BoardPoint(x: 42, y: 24)
        incoming.link?.summary = "Resumo novo"
        incoming.music?.subtitle = "Outro artista"
        incoming.colorTag = .green

        let merged = preserved(local, in: incoming)
        #expect(SharedFieldPolicy.shared(merged) == incoming)
        #expect(merged.keySentences == nil, "o texto mudou")
        #expect(merged.link?.previewImageFile == "A1B2.jpg")
        #expect(merged.music?.artworkFile == "capa.jpg")
    }
}
