import Foundation
import Testing

@testable import Mural

@MainActor
struct HapticFeedbackTests {
    @Test func doesNothingWhenDisabled() async throws {
        var taps = 0
        HapticFeedback.play(isEnabled: { false }, perform: { taps += 1 })
        try await Task.sleep(for: .milliseconds(150))
        #expect(taps == 0)
    }

    @Test func tapsTwiceWhenEnabled() async throws {
        var taps = 0
        HapticFeedback.play(isEnabled: { true }, perform: { taps += 1 })
        #expect(taps == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(taps == 2)
    }

    @Test func isEnabledByDefaultAndFollowsThePreference() throws {
        let suite = "HapticFeedbackTests-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        #expect(HapticFeedback.isEnabled(in: preferences))
        preferences.set(false, forKey: HapticFeedback.enabledKey)
        #expect(!HapticFeedback.isEnabled(in: preferences))
    }
}
