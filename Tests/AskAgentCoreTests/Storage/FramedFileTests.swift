import CryptoKit
import Testing

@testable import AskAgentCore

/// The framed container of ADR-0138: records given back as written, in each mode, and after the file is reopened.
@Suite
struct FramedFileTests {
    static let records: [[UInt8]] = [
        [], [0x7B], Array(#"{"kind":"message","text":"hello"}"#.utf8), [0x00, 0xFF, 0x00, 0x0A],
        (0 ..< 300_000).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) }
    ]

    @Test(arguments: FramedMode.allCases)
    func `each mode gives back its records`(mode: FramedMode) throws {
        let (bytes, _) = try mode.write(Self.records)
        let read = try FramedReader.read(bytes, key: mode.key)
        #expect(read.records == Self.records)
        #expect(read.ending == .clean)
        #expect(read.validLength == bytes.count)
    }

    @Test(arguments: FramedMode.allCases)
    func `appending after reopening continues the file`(mode: FramedMode) throws {
        let first = Array(Self.records.prefix(3))
        let (bytes, _) = try mode.write(first)
        var writer = try FramedWriter(resuming: FramedReader.read(bytes, key: mode.key), key: mode.key)
        var file = bytes
        for record in Self.records.dropFirst(3) { file += try writer.append(record) }
        #expect(try FramedReader.read(file, key: mode.key).records == Self.records)
    }

    @Test(arguments: [FramedMode.encrypted, .both])
    func `no two frames share a nonce, so a repeated record never shows`(mode: FramedMode) throws {
        let record = Array(#"{"same":"record"}"#.utf8)
        let (_, parts) = try mode.write(Array(repeating: record, count: 64))
        let nonces = parts.dropFirst()
            .map { Array($0[FrameFormat.frameHeaderLength ..< (FrameFormat.frameHeaderLength + 12)]) }
        #expect(Set(nonces).count == nonces.count)
    }

    @Test(arguments: FramedMode.allCases)
    func `any changed byte of the header is refused, never read past`(mode: FramedMode) throws {
        let (bytes, parts) = try mode.write(Array(Self.records.prefix(2)))
        for offset in 0 ..< parts[0].count {
            var changed = bytes
            changed[offset] ^= 0x01
            #expect(throws: FramedFileError.self, "header byte \(offset)") {
                _ = try FramedReader.read(changed, key: mode.key)
            }
        }
    }

    /// Real sessions (128 files, 2026-11-01) frame to 2.2 times smaller at zlib's default level, a flush per record included.
    @Test
    func `compressed records take under half their room`() throws {
        let records = (0 ..< 200)
            .map { Array(#"{"kind":"tool","name":"read","path":"Sources/File\#($0).swift","ok":true}"#.utf8) }
        let (bytes, _) = try FramedMode.compressed.write(records)
        #expect(bytes.count * 2 < records.reduce(0) { $0 + $1.count }, "\(bytes.count) bytes")
    }

    @Test
    func `a plain JSONL file, a cut header and a later version are told apart`() throws {
        #expect(throws: FramedFileError.notFramed) { try FramedReader.read(Array(#"{"a":1}"#.utf8), key: nil) }
        let header = try FramedWriter(compressed: true, key: nil).header.bytes
        for cut in 4 ..< header.count {
            #expect(throws: FramedFileError.truncatedHeader) { try FramedReader.read(Array(header[..<cut]), key: nil) }
        }
        var later = header
        later[4] = 2
        #expect(throws: FramedFileError.unsupportedVersion(2)) { try FramedReader.read(later, key: nil) }
    }

    @Test
    func `an encrypted file asks for a key, and the wrong one reads nothing`() throws {
        let (bytes, _) = try FramedMode.encrypted.write(Self.records)
        #expect(throws: FramedFileError.needsKey) { try FramedReader.read(bytes, key: nil) }
        let read = try FramedReader.read(bytes, key: SymmetricKey(size: .bits256))
        #expect(read.records.isEmpty)
        #expect(read.ending == .damaged(frame: 0))
    }
}
