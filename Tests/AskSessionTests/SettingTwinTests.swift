import AskAgentCore
import AskTUI
import Testing

/// Every choice a `ui` setting offers has its twin on the screen (roadmap 0209, step 1). The configuration's enumeration and the
/// screen's are bridged by their raw values (`RunSettings.word`), and a case with no twin falls back to the screen's default without a
/// word. This test holds them together until ADR-0166 makes each one type, when it has nothing left to check and goes.
@Suite("Every ui choice has its twin on the screen")
struct SettingTwinTests {
    /// The cases of `setting` that `screen` cannot name.
    private func orphans<Setting: RawRepresentable & CaseIterable, Screen: RawRepresentable>(
        _ setting: Setting.Type,
        _ screen: Screen.Type
    ) -> [String] where Setting.RawValue == String, Screen.RawValue == String {
        setting.allCases.map(\.rawValue).filter { Screen(rawValue: $0) == nil }
    }

    @Test func `every choice a ui setting offers names a case on the screen`() {
        let found: [String: [String]] = [
            "spinner": orphans(SpinnerPreference.self, SpinnerStyle.self),
            "showTimeout": orphans(TimeoutPreference.self, TimeoutDisplay.self),
            "notify": orphans(NotifyPreference.self, NotifyStyle.self),
            "statusPath": orphans(StatusPathPreference.self, StatusPathForm.self),
            "statusPathSide": orphans(StatusPathSidePreference.self, StatusPathSide.self)
        ]
        let orphaned = found.filter { !$0.value.isEmpty }
        #expect(orphaned.isEmpty, "choices the screen cannot name: \(orphaned)")
    }

    /// `dot` and `star` are still read and drawn as the default (roadmap 0171), so they are left out of `allCases` on purpose.
    @Test func `the spinners only still read are the ones the screen draws as its default`() {
        #expect(SpinnerStyle(rawValue: SpinnerPreference.dot.rawValue) == nil)
        #expect(SpinnerStyle(rawValue: SpinnerPreference.star.rawValue) == nil)
    }
}
