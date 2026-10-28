internal import AemiJSON

/// Append-only JSON Lines encoding of a ``SessionTree``.
///
/// A log is a header, one record per entry in archive order, and optional leaf records for checkouts.
/// Appending a record never rewrites earlier bytes, so a crash can damage only the final line — which
/// ``decode(_:limits:)`` reports as ``SessionLogError/tornFinalLine(line:)`` rather than dropping.
///
/// Pure: bytes in, bytes out. File placement, locking and fsync policy belong to the caller.
public enum SessionLog {
    /// The writer version. Version 1 remains readable; version 2 protects routing from older readers.
    public static let formatVersion = 2

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
        try snapshot(tree, images: nil)
    }

    /// ``snapshot(_:)`` with the pictures of tool results written to `images` and referenced by hash.
    static func snapshot(_ tree: SessionTree, images: SessionImageStore?) throws(SessionLogError) -> [UInt8] {
        var bytes = try encode(.header(version: formatVersion))
        for entry in tree.entries { bytes += try encode(.entry(entry), images: images) }
        if let sandbox = tree.sandbox { bytes += try encode(.sandbox(sandbox)) }
        bytes += try encode(.leaf(tree.leaf))
        return bytes
    }

    /// One newline-terminated record appending `entry`. Replay selects it as the leaf.
    /// - Parameter entry: the entry to append.
    /// - Returns: the record's bytes.
    /// - Throws: ``SessionLogError/encodingFailed``.
    public static func line(for entry: SessionEntry) throws(SessionLogError) -> [UInt8] {
        try line(for: entry, images: nil)
    }

    /// ``line(for:)`` with the pictures of tool results written to `images` and referenced by hash.
    static func line(for entry: SessionEntry, images: SessionImageStore?) throws(SessionLogError) -> [UInt8] {
        try encode(.entry(entry), images: images)
    }

    /// One newline-terminated record selecting `leaf`, or a new root when nil.
    /// - Parameter leaf: the entry to select.
    /// - Returns: the record's bytes.
    /// - Throws: ``SessionLogError/encodingFailed``.
    public static func line(forLeaf leaf: EntryID?) throws(SessionLogError) -> [UInt8] {
        try encode(.leaf(leaf))
    }

    /// One newline-terminated record saying the session now runs under `sandbox`'s strict settings.
    /// - Throws: ``SessionLogError/encodingFailed``.
    public static func line(forSandbox sandbox: SandboxSection) throws(SessionLogError) -> [UInt8] {
        try encode(.sandbox(sandbox.strict))
    }

    /// Loads a log, repairing damage and reporting each repair. The default way to open a session.
    ///
    /// Damage costs only what is damaged, and the file is never written (ADR-0013): torn and
    /// corrupt lines are skipped, orphans become roots, a compaction with an off-branch boundary is
    /// spliced out, and every such repair is listed in ``RecoveredSession/issues``.
    /// - Parameters:
    ///   - bytes: the whole archive.
    ///   - limits: ceilings applied before any parsing.
    /// - Returns: a valid tree and the repairs made.
    /// - Throws: only what cannot be repaired safely: ``SessionLogError/archiveTooLarge(_:)`` and
    ///   ``SessionLogError/unsupportedVersion(_:)``.
    /// - Complexity: O(n) in the archive size, plus tree validation.
    public static func recover(
        _ bytes: [UInt8], limits: Limits = .standard
    ) throws(SessionLogError) -> RecoveredSession {
        try recover(bytes, limits: limits, images: nil)
    }

    /// ``recover(_:limits:)`` reading the pictures of tool results from `images`. A picture it cannot find becomes a line of text.
    static func recover(
        _ bytes: [UInt8], limits: Limits, images: SessionImageStore?
    ) throws(SessionLogError) -> RecoveredSession {
        guard bytes.count <= limits.maximumArchiveBytes else { throw .archiveTooLarge(bytes.count) }
        guard !bytes.isEmpty else { return RecoveredSession(tree: SessionTree(), issues: [.missingHeader]) }
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        // Empty when the archive ends in a newline, as every complete write does.
        let finalLine = lines.removeLast()
        var recovery = Recovery(limits: limits, images: images)
        for (index, line) in lines.enumerated() {
            try recovery.consume(line, number: index + 1, isFinal: false)
        }
        if !finalLine.isEmpty { try recovery.consume(finalLine, number: lines.count + 1, isFinal: true) }
        return RecoveredSession(tree: recovery.tree, issues: recovery.issues, formatVersion: recovery.version)
    }

    /// Loads a log only if it is undamaged. For validation and tests; sessions open with ``recover(_:limits:)``.
    /// - Parameters:
    ///   - bytes: the whole archive.
    ///   - limits: ceilings applied before any parsing.
    /// - Returns: the session.
    /// - Throws: the first issue ``recover(_:limits:)`` would have repaired, as a ``SessionLogError``.
    public static func decode(
        _ bytes: [UInt8], limits: Limits = .standard
    ) throws(SessionLogError) -> SessionTree {
        let recovered = try recover(bytes, limits: limits)
        if let issue = recovered.issues.first { throw issue.strictError }
        return recovered.tree
    }

    /// Replay with repairs. Each record either applies, applies after a stated repair, or is skipped and
    /// reported; the tree is valid after every step.
    private struct Recovery {
        let limits: Limits
        var decoder = AemiJSON.JSONDecoder()
        var tree = SessionTree()
        var issues: [SessionLogIssue] = []
        var version = SessionLog.formatVersion
        private var headerSeen = false
        private var missingHeaderReported = false
        /// Spliced-out compactions, mapped to the parent their children now attach to.
        private var spliced: [EntryID: EntryID?] = [:]

        init(limits: Limits, images: SessionImageStore?) {
            self.limits = limits
            if let images { decoder.userInfo[SessionImageStore.userInfoKey] = images }
        }

        mutating func consume(_ line: ArraySlice<UInt8>, number: Int, isFinal: Bool) throws(SessionLogError) {
            guard line.count <= limits.maximumLineBytes else {
                issues.append(.lineTooLong(line: number))
                return
            }
            let record: SessionLogRecord
            do {
                // The one copy at the boundary: the decoder reads a contiguous `[UInt8]`.
                record = try decoder.decode(SessionLogRecord.self, from: Array(line))
            } catch {
                issues.append(isFinal ? .tornFinalLine(line: number) : .malformedLine(line: number))
                return
            }
            try apply(record, line: number)
            if isFinal { issues.append(.unterminatedFinalLine(line: number)) }
        }

        private mutating func apply(_ record: SessionLogRecord, line: Int) throws(SessionLogError) {
            if case .header(let version) = record {
                guard !headerSeen, line == 1 else {
                    issues.append(.malformedLine(line: line))
                    return
                }
                guard version == 1 || version == SessionLog.formatVersion else { throw .unsupportedVersion(version) }
                self.version = version
                headerSeen = true
                return
            }
            if !headerSeen, !missingHeaderReported {
                issues.append(.missingHeader)
                missingHeaderReported = true
            }
            switch record {
                case .header: break
                case .entry(let entry): restore(entry, line: line)
                case .leaf(let id): select(id, line: line)
                case .sandbox(let section): tree.recordSandbox(section)
            }
        }

        private mutating func restore(_ original: SessionEntry, line: Int) {
            var entry = original
            if let parent = entry.parentID, let replacement = spliced[parent] {
                entry = SessionEntry(id: entry.id, parentID: replacement, payload: entry.payload)
            }
            // At most two attempts: as written, then re-rooted when the parent is missing.
            for _ in 0 ..< 2 {
                do {
                    try tree.restore(entry)
                    return
                } catch .unknownEntry(let missing) {
                    issues.append(.orphanedEntry(entry.id, missingParent: missing, line: line))
                    entry = SessionEntry(id: entry.id, parentID: nil, payload: entry.payload)
                } catch .invalidCompactionBoundary(let boundary) {
                    issues.append(.droppedCompaction(entry.id, boundary: boundary, line: line))
                    spliced[entry.id] = .some(entry.parentID)
                    return
                } catch .duplicateEntry(let id) {
                    issues.append(.duplicateEntry(id, line: line))
                    return
                } catch .invalidIdentifier(let id) {
                    issues.append(.invalidIdentifier(id, line: line))
                    return
                } catch {
                    // `restore` mints no identifiers, so exhaustion cannot occur; skip rather than trap.
                    issues.append(.malformedLine(line: line))
                    return
                }
            }
        }

        private mutating func select(_ id: EntryID?, line: Int) {
            // A leaf naming a spliced compaction lands where the compaction's children now attach.
            let target: EntryID? = id.flatMap { named in spliced[named] ?? named }
            do {
                try tree.moveLeaf(to: target)
            } catch {
                // Only a named, unknown entry can fail; selecting a new root cannot.
                if let id { issues.append(.ignoredLeaf(id, line: line)) }
            }
        }
    }

    private static func encode(
        _ record: SessionLogRecord, images: SessionImageStore? = nil
    ) throws(SessionLogError) -> [UInt8] {
        var encoder = AemiJSON.JSONEncoder()
        if let images { encoder.userInfo[SessionImageStore.userInfoKey] = images }
        // Sorted keys make equal records byte-identical; slashes stay unescaped, AemiJSON's default.
        encoder.options.keyOrder = .sorted
        do {
            var bytes = try encoder.encodeToBytes(record)
            bytes.append(0x0A)
            return bytes
        } catch {
            throw .encodingFailed
        }
    }
}
