import CryptoKit
import Testing

@testable import AskAgentCore

/// The three ways a framed file can be written: compressed, encrypted, or both (plain stays JSONL, outside the container).
enum FramedMode: String, CaseIterable, CustomTestStringConvertible {
    case compressed, encrypted, both

    static let sharedKey = SymmetricKey(size: .bits256)

    var key: SymmetricKey? { self == .compressed ? nil : Self.sharedKey }
    var testDescription: String { rawValue }

    /// The file's bytes, and its parts: the header, then each frame appended.
    func write(_ records: [[UInt8]]) throws -> ([UInt8], [[UInt8]]) {
        var writer = try FramedWriter(compressed: self != .encrypted, key: key)
        var parts = [writer.header.bytes]
        for record in records { parts.append(try writer.append(record)) }
        return (parts.flatMap { $0 }, parts)
    }
}
