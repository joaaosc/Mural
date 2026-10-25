import Foundation
import MuralSync
import Testing

@testable import Mural

/// O que o indicador de sincronização mostra para cada aviso do mural.
struct SyncStatusIndicatorTests {
    @Test func withoutIssueShowsSynced() {
        let display = SyncStatusDisplay(issue: nil)
        #expect(display.symbolName == "checkmark.icloud")
        #expect(display.text == "Sincronizado com o iCloud")
        #expect(!display.isWarning)
    }

    @Test func quotaExceededWarnsAboutOwnersSpace() {
        let display = SyncStatusDisplay(issue: .quotaExceeded)
        #expect(display.symbolName == "exclamationmark.icloud")
        #expect(display.text == "Sem espaço no iCloud do dono do mural")
        #expect(display.isWarning)
    }

    @Test func awaitingFirstFetchIsInformativeNotAWarning() {
        let display = SyncStatusDisplay(issue: .awaitingFirstFetch)
        #expect(display.symbolName == "icloud.and.arrow.down")
        #expect(display.text == "Baixando do iCloud…")
        #expect(!display.isWarning)
    }

    @Test func readOnlyIsNotAWarning() {
        let display = SyncStatusDisplay(issue: .readOnly)
        #expect(display.symbolName == "icloud")
        #expect(display.text == "Você só pode ver este mural")
        #expect(!display.isWarning)
    }

    @Test(arguments: [
        SyncIssue.recordTooLarge(UUID()), .needsNewerApp, .localSaveFailed, .other("detalhe técnico"),
    ])
    func otherIssuesWarnWithOwnText(issue: SyncIssue) {
        let display = SyncStatusDisplay(issue: issue)
        #expect(display.symbolName == "exclamationmark.icloud")
        #expect(display.isWarning)
        #expect(!display.text.isEmpty)
        #expect(!display.text.contains("detalhe técnico"))
    }

    @Test func eachIssueHasItsOwnText() {
        let issues: [SyncIssue?] = [
            nil, .quotaExceeded, .readOnly, .recordTooLarge(UUID()), .needsNewerApp, .localSaveFailed, .awaitingFirstFetch, .other("x"),
        ]
        let texts = issues.map { SyncStatusDisplay(issue: $0).text }
        #expect(Set(texts).count == issues.count)
    }
}
