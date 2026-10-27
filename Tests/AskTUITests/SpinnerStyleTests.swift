internal import Foundation
internal import TerminalKitText
internal import Testing

@testable import AskTUI

@Suite("Spinner styles and frame width constraints")
struct SpinnerStyleTests {
    @Test func `all configured spinner frames have strictly width 1`() {
        for style in SpinnerStyle.allConcrete {
            for frame in style.frames {
                let width = UnicodeWidth.displayWidth(of: frame)
                #expect(width == 1, "Style \(style) frame \(frame) has width \(width) != 1")
            }
        }
    }

    @Test func `random spinner selects among the specific styles`() {
        var seen: Set<SpinnerStyle> = []
        for _ in 0 ..< 100 {
            seen.insert(SpinnerStyle.randomConcrete())
        }
        #expect(seen.count > 1)
        #expect(!seen.contains(.random))
    }
}
