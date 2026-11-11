import Testing

@testable import AskTUI

/// Whether an output needs reading for escapes, decided in one pass over its bytes (note n47, t233): it was two passes through
/// `String.UTF8View` one byte at a time, a sixth of a long session's resume.
@Suite("An output is read for escapes exactly when it holds one or a control")
struct OutputEscapesScanTests {
    /// What the decision was before: an escape, a C1 lead byte, or a control but tab, line feed and carriage return.
    private static func reference(_ raw: String) -> Bool {
        raw.utf8.contains { $0 == 0x1B || $0 == 0xC2 }
            || raw.utf8.contains { ($0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D) || $0 == 0x7F }
    }

    @Test func `every byte alone, and inside plain text, decides as before`() {
        var scalars = (0 ..< 0x80).map { Unicode.Scalar(UInt8($0)) }
        scalars += ["·", "é", "🙂", "\u{85}", "\u{9B}"]
        for scalar in scalars {
            let alone = String(Character(scalar))
            let inside = String(repeating: "plain text, ", count: 40) + alone + " and after"
            #expect(OutputEscapes.needsReading(alone) == Self.reference(alone), "\(scalar.value)")
            #expect(OutputEscapes.needsReading(inside) == Self.reference(inside), "\(scalar.value)")
        }
    }

    @Test func `plain text, with tabs and both line ends, needs no reading`() {
        #expect(!OutputEscapes.needsReading(""))
        #expect(!OutputEscapes.needsReading(String(repeating: "a line\twith tabs été 🙂\r\n", count: 1_000)))
        #expect(OutputEscapes.needsReading(String(repeating: "x", count: 10_000) + "\u{1B}[31m"))
    }

    @Test func `a bridged string decides as a native one`() {
        let native = "a\u{1B}[1mb"
        #expect(OutputEscapes.needsReading(String(native.utf16.map { Character(Unicode.Scalar($0)!) })))
    }
}
