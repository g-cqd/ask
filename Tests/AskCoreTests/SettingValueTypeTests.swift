import AskCore
import Testing

/// The value types a setting and the screen share, declared once (ADR-0166, roadmap 0209). Their twins are gone, so no test holds two
/// enumerations together any more; what is left to say is which choices are offered.
@Suite("The settings' shared value types")
struct SettingValueTypeTests {
    /// `dot` and `star` are still read and drawn as the default (roadmap 0171), so they are left out of what is offered.
    @Test func `the spinners only still read are not offered, and every other one is`() {
        #expect(SpinnerStyle.dot.isOnlyRead && SpinnerStyle.star.isOnlyRead)
        let offered = SpinnerStyle.allCases
        #expect(offered.filter(\.isOnlyRead).isEmpty)
        let concreteOffered = SpinnerStyle.allConcrete.filter { offered.contains($0) }
        #expect(offered.count == 6 && concreteOffered == SpinnerStyle.allConcrete)
    }
}
