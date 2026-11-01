import CryptoKit
import Testing

@testable import AskAgentCore

/// The scanner sessions are opened with: a chunk at a time, holding a frame and not the file, with a ceiling on what a record may
/// decompress to.
@Suite
struct FrameScannerTests {
    static let records = (0 ..< 6)
        .map {
            Array(#"{"n":\#($0),"text":"a record of a session, long enough to span chunks"}"#.utf8)
        }

    /// The records and the ending, the file fed `chunk` bytes at a time.
    static func scan(
        _ bytes: [UInt8],
        chunk: Int,
        key: SymmetricKey?,
        limit: Int = .max
    ) throws -> ([[UInt8]?], FramedEnding) {
        var scanner = FrameScanner(key: key, recordLimit: limit)
        var records: [[UInt8]?] = []
        for start in stride(from: 0, to: bytes.count, by: chunk) {
            try scanner.feed(bytes[start ..< min(start + chunk, bytes.count)]) { record in
                if case .bytes(let bytes) = record { records.append(bytes) } else { records.append(nil) }
            }
        }
        return (records, try scanner.finish())
    }

    @Test(arguments: FramedMode.allCases, [1, 7, 4096])
    func `fed in chunks it reads what it reads whole, cut or changed`(mode: FramedMode, chunk: Int) throws {
        let (bytes, parts) = try mode.write(Self.records)
        let whole = try Self.scan(bytes, chunk: bytes.count, key: mode.key)
        let chunked = try Self.scan(bytes, chunk: chunk, key: mode.key)
        #expect(chunked.0 == whole.0 && chunked.1 == .clean)
        let cut = Array(bytes.dropLast(3))
        #expect(try Self.scan(cut, chunk: chunk, key: mode.key).1 == .tornTail)
        var changed = bytes
        changed[parts[0].count + parts[1].count + 12] ^= 0x10
        let damaged = try Self.scan(changed, chunk: chunk, key: mode.key)
        #expect(damaged.1 == .damaged(frame: 1))
        #expect(damaged.0.count == 1)
    }

    @Test(arguments: [FramedMode.compressed, .both])
    func `a record that decompresses past the limit is dropped, and the records after it still read`(mode: FramedMode)
        throws
    {
        let bomb = [UInt8](repeating: 0x41, count: 4 << 20)
        let (bytes, parts) = try mode.write([Self.records[0], bomb, Self.records[1]])
        #expect(parts[2].count < 64 << 10, "the bomb is small on disk: \(parts[2].count) bytes")
        let (records, ending) = try Self.scan(bytes, chunk: 4096, key: mode.key, limit: 1 << 20)
        #expect(records == [Self.records[0], nil, Self.records[1]])
        #expect(ending == .clean)
    }
}
