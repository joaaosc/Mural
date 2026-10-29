import Testing

@testable import Mural

@Suite("Captura do atalho nas configurações")
@MainActor
struct HotKeyRecorderTests {
    @Test("Só captura eventos da janela ativa enquanto o gravador tem foco")
    func onlyCapturesInFocusedRecorderWindow() {
        #expect(
            HotKeyCapturePolicy.shouldHandle(
                eventWindowIsRecorderWindow: true, recorderWindowIsKey: true, recorderIsFocused: true))
        #expect(
            !HotKeyCapturePolicy.shouldHandle(
                eventWindowIsRecorderWindow: false, recorderWindowIsKey: true, recorderIsFocused: true))
        #expect(
            !HotKeyCapturePolicy.shouldHandle(
                eventWindowIsRecorderWindow: true, recorderWindowIsKey: false, recorderIsFocused: true))
        #expect(
            !HotKeyCapturePolicy.shouldHandle(
                eventWindowIsRecorderWindow: true, recorderWindowIsKey: true, recorderIsFocused: false))
    }
}
