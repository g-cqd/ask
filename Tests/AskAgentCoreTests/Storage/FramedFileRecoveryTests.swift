import CryptoKit
import Testing

@testable import AskAgentCore

/// What a framed file says when it was cut by a crash or changed afterwards (ADR-0138, section 3): a cut last frame is a torn tail,
/// dropped; anything wrong before the last frame is damage, and the records before it are kept.
@Suite
struct FramedFileRecoveryTests {
    static let records = (0 ..< 4).map { Array(#"{"n":\#($0),"text":"some record of a session"}"#.utf8) }

    @Test(arguments: FramedMode.allCases)
    func `a file cut anywhere in its last frame drops that record only`(mode: FramedMode) throws {
        let (bytes, parts) = try mode.write(Self.records)
        let lastStart = bytes.count - parts.last!.count
        for cut in lastStart ..< bytes.count {
            let read = try FramedReader.read(Array(bytes[..<cut]), key: mode.key)
            #expect(read.records == Array(Self.records.dropLast()), "cut at \(cut)")
            #expect(read.ending == (cut == lastStart ? .clean : .tornTail), "cut at \(cut)")
            #expect(read.validLength == lastStart, "cut at \(cut)")
        }
    }

    @Test(arguments: FramedMode.allCases)
    func `any changed byte of a frame before the last makes the file damaged, keeping what precedes`(mode: FramedMode)
        throws
    {
        let (bytes, parts) = try mode.write(Self.records)
        let start = parts[0].count + parts[1].count
        for offset in start ..< start + parts[2].count {
            for bit in [0, 7] {
                var changed = bytes
                changed[offset] ^= 1 << bit
                let read = try FramedReader.read(changed, key: mode.key)
                #expect(read.records == [Self.records[0]], "byte \(offset - start) bit \(bit)")
                #expect(read.ending == .damaged(frame: 1), "byte \(offset - start) bit \(bit)")
                #expect(read.validLength == start, "byte \(offset - start) bit \(bit)")
            }
        }
    }

    @Test(arguments: [FramedMode.encrypted, .both])
    func `encrypted frames cannot be reordered, dropped or moved from another file`(mode: FramedMode) throws {
        let (_, parts) = try mode.write(Self.records)
        let swapped = parts[0] + parts[2] + parts[1] + parts[3] + parts[4]
        #expect(try FramedReader.read(swapped, key: mode.key).ending == .damaged(frame: 0))
        let dropped = parts[0] + parts[1] + parts[3] + parts[4]
        #expect(try FramedReader.read(dropped, key: mode.key).ending == .damaged(frame: 1))
        let (_, other) = try mode.write(Self.records)
        let moved = parts[0] + parts[1] + other[2] + parts[3] + parts[4]
        #expect(try FramedReader.read(moved, key: mode.key).ending == .damaged(frame: 1))
    }

    @Test
    func `a damaged or torn file cannot be appended to as it is`() throws {
        let (bytes, _) = try FramedMode.both.write(Self.records)
        let torn = try FramedReader.read(Array(bytes.dropLast()), key: FramedMode.sharedKey)
        #expect(throws: FramedFileError.notResumable) {
            _ = try FramedWriter(resuming: torn, key: FramedMode.sharedKey)
        }
    }
}
