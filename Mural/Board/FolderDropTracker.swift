import Foundation

/// Decide em qual pasta o cartão arrastado seria guardado se fosse solto agora.
///
/// A pasta que já estava sob o ponteiro quando o arrasto começou (um post-it por cima de uma
/// pasta, por exemplo) só vira candidata depois que o ponteiro sai dela uma vez: um empurrão no
/// post-it não deve guardá-lo na pasta de baixo.
///
/// A candidata só vira destino depois de ficar `armingDelay` sob o ponteiro: soltar antes disso
/// apenas reposiciona. Trocar de pasta ou sair dela zera a espera. O tempo entra por parâmetro
/// para a regra ser testável sem esperar.
struct FolderDropTracker: Equatable {
    /// Quanto o ponteiro precisa ficar sobre a pasta para ela aceitar o cartão, em segundos.
    static let armingDelay: TimeInterval = 1.5

    /// Pasta sob o ponteiro no começo do arrasto, enquanto o ponteiro ainda não saiu dela.
    private(set) var startFolder: UUID?
    /// Pasta elegível sob o ponteiro agora, ainda esperando (ou já liberada); `nil` fora de qualquer pasta.
    private(set) var candidate: UUID?
    /// Quando a candidata atual passou a ficar sob o ponteiro.
    private(set) var enteredAt: Date?
    /// A candidata já esperou o suficiente e aceita o cartão.
    private(set) var isArmed = false

    /// Pasta que receberia o cartão agora; `nil` quando soltar só reposiciona.
    var target: UUID? { isArmed ? candidate : nil }

    init(startFolder: UUID?) {
        self.startFolder = startFolder
    }

    /// Atualiza com a pasta sob o ponteiro agora (`nil` fora de qualquer pasta).
    mutating func update(folderUnderPointer folder: UUID?, now: Date = .now) {
        if startFolder != nil, folder != startFolder { startFolder = nil }
        let eligible = folder == startFolder ? nil : folder
        guard eligible != candidate else { return }
        candidate = eligible
        enteredAt = eligible == nil ? nil : now
        isArmed = false
    }

    /// Libera a candidata se ela já esperou `armingDelay`. Devolve verdadeiro quando acabou de ser liberada.
    @discardableResult
    mutating func arm(now: Date = .now) -> Bool {
        guard !isArmed, candidate != nil, let enteredAt, now.timeIntervalSince(enteredAt) >= Self.armingDelay else {
            return false
        }
        isArmed = true
        return true
    }

    /// Libera a candidata sem esperar, para telas em que não há atraso (a grade da coleção).
    mutating func armImmediately() {
        isArmed = candidate != nil
    }
}
