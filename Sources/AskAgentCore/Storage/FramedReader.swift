internal import CryptoKit

/// Reads a whole framed file held in memory: ``FrameScanner`` over one chunk. Sessions are read with the scanner, a chunk at a time.
enum FramedReader {
    static func read(_ bytes: [UInt8], key: SymmetricKey?) throws(FramedFileError) -> FramedRead {
        var scanner = FrameScanner(key: key)
        var records: [[UInt8]] = []
        try scanner.feed(bytes[...]) { record in
            if case .bytes(let bytes) = record { records.append(bytes) }
        }
        let ending = try scanner.finish()
        guard let header = scanner.header else { throw .truncatedHeader }
        return FramedRead(
            header: header,
            records: records,
            ending: ending,
            validLength: scanner.validLength,
            frameCount: scanner.frameCount
        )
    }
}
