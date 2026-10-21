import Foundation
import NaturalLanguage
import Observation
import StretchText
import StretchTextGeneration

/// Escolhe em segundo plano, com o modelo do aparelho, as frases curtas das notas
/// e das aberturas de lista.
///
/// Um cartão por vez, porque o modelo recusa pedidos simultâneos; o cartão aberto
/// na tela passa à frente. Cada texto é tentado uma vez por sessão: uma falha não
/// vira laço. Nada é gravado aqui: o texto atual vem de `source` e o resultado vai
/// para `apply`, que confere se o texto ainda é o mesmo antes de guardar.
@MainActor
@Observable
public final class KeySentenceCoordinator {
    /// Cartão que o modelo está dobrando agora.
    public private(set) var currentItemID: UUID?

    @ObservationIgnored private let picker: any KeySentencePicker
    @ObservationIgnored private let timeLimit: Duration
    @ObservationIgnored private let locale: @Sendable (String) -> Locale
    @ObservationIgnored private let source: (UUID) -> String?
    @ObservationIgnored private let apply: (UUID, KeySentenceRecord) -> Void
    @ObservationIgnored private var queue: [UUID] = []
    /// Hash do último texto tentado de cada cartão nesta sessão.
    @ObservationIgnored private var attempted: [UUID: String] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerGeneration: UInt64 = 0

    public init(
        picker: any KeySentencePicker = CachingKeySentencePicker(base: ModelKeySentencePicker(), cache: KeySentenceCache()),
        timeLimit: Duration = .seconds(60),
        locale: @escaping @Sendable (String) -> Locale = KeySentenceCoordinator.dominantLocale(of:),
        source: @escaping (UUID) -> String?,
        apply: @escaping (UUID, KeySentenceRecord) -> Void
    ) {
        self.picker = picker
        self.timeLimit = timeLimit
        self.locale = locale
        self.source = source
        self.apply = apply
    }

    /// Põe o cartão na fila, se o texto atual ainda não foi tentado nesta sessão.
    /// `first` passa à frente dos outros (a nota aberta na tela).
    public func enqueue(_ itemID: UUID, first: Bool = false) {
        guard let text = source(itemID), attempted[itemID] != KeySentenceRecord.hash(of: text) else { return }
        queue.removeAll { $0 == itemID }
        if first {
            queue.insert(itemID, at: 0)
        } else {
            queue.append(itemID)
        }
        startIfNeeded()
    }

    /// Para tudo: a escolha em andamento é cancelada e nada dela é gravado.
    public func cancelAll() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        workerGeneration &+= 1
        currentItemID = nil
    }

    /// Espera a fila esvaziar.
    public func waitUntilIdle() async {
        while let worker {
            await worker.value
        }
    }

    // MARK: Fila

    private func startIfNeeded() {
        guard worker == nil else { return }
        workerGeneration &+= 1
        let generation = workerGeneration
        worker = Task { [weak self] in
            await self?.drain(generation)
        }
    }

    private func drain(_ generation: UInt64) async {
        while !Task.isCancelled, generation == workerGeneration, !queue.isEmpty {
            await process(queue.removeFirst())
        }
        if generation == workerGeneration {
            worker = nil
        }
    }

    private func process(_ itemID: UUID) async {
        guard let text = source(itemID) else { return }
        let hash = KeySentenceRecord.hash(of: text)
        guard attempted[itemID] != hash else { return }
        attempted[itemID] = hash
        currentItemID = itemID
        defer { if currentItemID == itemID { currentItemID = nil } }

        let folder = KeySentenceFolder(picker: picker, policy: .useFirstSentence, timeLimit: timeLimit)
        do {
            let result = try await folder.fold(TextSegmenter.segment(text), locale: locale(text))
            apply(itemID, KeySentenceRecord(source: text, fold: result.fold))
        } catch .cancelled {
            // Interrompida (janela fechou, cartão apagado): pode ser tentada de novo depois.
            attempted[itemID] = nil
        } catch {
            // O seletor devolveu escolhas que não montam o texto: fica a primeira frase.
        }
    }

    // MARK: Idioma

    /// Idioma predominante do texto, com a região preferida do sistema quando ela
    /// existir para esse idioma (`pt` → `pt-BR`). Sem idioma claro, o do sistema.
    public nonisolated static func dominantLocale(of text: String) -> Locale {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return .current }
        let code = language.rawValue
        let preferred = Locale.preferredLanguages.first { Locale(identifier: $0).language.languageCode?.identifier == code }
        return Locale(identifier: preferred ?? code)
    }
}
