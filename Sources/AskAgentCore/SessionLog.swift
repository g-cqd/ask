internal import Foundation

/// Append-only JSON Lines encoding of a ``SessionTree``.
///
/// A log is a header, one record per entry in archive order, and optional leaf records for checkouts.
/// Appending a record never rewrites earlier bytes, so a crash can damage only the final line — which
/// ``decode(_:limits:)`` reports as ``SessionLogError/tornFinalLine(line:)`` rather than dropping.
///
/// Pure: bytes in, bytes out. File placement, locking and fsync policy belong to the caller.
public enum SessionLog {
    /// The only format version this build reads or writes.
    public static let formatVersion = 1

    /// Ceilings checked before parsing, so a hostile archive cannot exhaust memory in the decoder.
    public struct Limits: Sendable, Equatable {
        /// Longest accepted line, in bytes.
        public var maximumLineBytes: Int
        /// Largest accepted archive, in bytes.
        public var maximumArchiveBytes: Int

        /// Creates limits.
        /// - Parameters:
        ///   - maximumLineBytes: longest accepted line, in bytes.
        ///   - maximumArchiveBytes: largest accepted archive, in bytes.
        public init(maximumLineBytes: Int, maximumArchiveBytes: Int) {
            self.maximumLineBytes = maximumLineBytes
            self.maximumArchiveBytes = maximumArchiveBytes
        }

        /// 1 MiB per line, matching the tool-output ceiling in roadmap 0011; 64 MiB per archive.
        /// Policy values, not measurements.
        public static let standard = Limits(maximumLineBytes: 1 << 20, maximumArchiveBytes: 64 << 20)
    }

    /// The whole session: header, every entry in archive order, then the current leaf.
    /// - Parameter tree: the session to encode.
    /// - Returns: newline-terminated JSON Lines, deterministic for equal trees.
    /// - Throws: ``SessionLogError/encodingFailed``.
    /// - Complexity: O(total payload size).
    public static func snapshot(_ tree: SessionTree) throws(SessionLogError) -> [UInt8] {
        var bytes = try encode(.header(version: formatVersion))
        for entry in tree.entries { bytes += try encode(.entry(entry)) }
        bytes += try encode(.leaf(tree.leaf))
        return bytes
    }

    /// One newline-terminated record appending `entry`. Replay selects it as the leaf.
    /// - Parameter entry: the entry to append.
    /// - Returns: the record's bytes.
    /// - Throws: ``SessionLogError/encodingFailed``.
    public static func line(for entry: SessionEntry) throws(SessionLogError) -> [UInt8] {
        try encode(.entry(entry))
    }

    /// One newline-terminated record selecting `leaf`, or a new root when nil.
    /// - Parameter leaf: the entry to select.
    /// - Returns: the record's bytes.
    /// - Throws: ``SessionLogError/encodingFailed``.
    public static func line(forLeaf leaf: EntryID?) throws(SessionLogError) -> [UInt8] {
        try encode(.leaf(leaf))
    }

    /// Replays a log into a session, or throws; never returns a partially read session.
    /// - Parameters:
    ///   - bytes: the whole archive.
    ///   - limits: ceilings applied before any parsing.
    /// - Returns: the restored session.
    /// - Throws: ``SessionLogError``, with 1-based line numbers.
    /// - Complexity: O(n) in the archive size, plus tree validation.
    public static func decode(
        _ bytes: [UInt8], limits: Limits = .standard
    ) throws(SessionLogError) -> SessionTree {
        guard bytes.count <= limits.maximumArchiveBytes else { throw .archiveTooLarge(bytes.count) }
        guard !bytes.isEmpty else { throw .missingHeader }
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard let tail = lines.popLast(), tail.isEmpty else { throw .tornFinalLine(line: lines.count + 1) }

        let decoder = JSONDecoder()
        var replay = Replay()
        for (index, line) in lines.enumerated() {
            let number = index + 1
            guard line.count <= limits.maximumLineBytes else { throw .lineTooLong(line: number) }
            let record: SessionLogRecord
            do {
                // The one copy at the boundary: JSONDecoder reads `Data`.
                record = try decoder.decode(SessionLogRecord.self, from: Data(line))
            } catch {
                throw .malformedLine(line: number)
            }
            try replay.apply(record, line: number)
        }
        return try replay.tree()
    }

    /// The replay state: records in order, then one validated tree at the end.
    private struct Replay {
        private var entries: [SessionEntry] = []
        private var written = Set<EntryID>()
        private var leaf: EntryID?

        mutating func apply(_ record: SessionLogRecord, line: Int) throws(SessionLogError) {
            switch record {
                case .header(let version):
                    guard line == 1 else { throw .malformedLine(line: line) }
                    guard version == formatVersion else { throw .unsupportedVersion(version) }
                case .entry(let entry):
                    guard line > 1 else { throw .missingHeader }
                    entries.append(entry)
                    written.insert(entry.id)
                    leaf = entry.id
                case .leaf(let id):
                    guard line > 1 else { throw .missingHeader }
                    if let id, !written.contains(id) { throw .invalidArchive(.unknownEntry(id)) }
                    leaf = id
            }
        }

        func tree() throws(SessionLogError) -> SessionTree {
            do {
                return try SessionTree(entries: entries, leaf: leaf)
            } catch {
                throw .invalidArchive(error)
            }
        }
    }

    private static func encode(_ record: SessionLogRecord) throws(SessionLogError) -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            var bytes = [UInt8](try encoder.encode(record))
            bytes.append(0x0A)
            return bytes
        } catch {
            throw .encodingFailed
        }
    }
}
