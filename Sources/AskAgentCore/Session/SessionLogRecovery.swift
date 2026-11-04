internal import AemiJSON

/// Replay with repairs. Each record either applies, applies after a stated repair, or is skipped and
/// reported; the tree is valid after every step.
struct SessionLogRecovery {
    let limits: SessionLog.Limits
    var decoder = AemiJSON.JSONDecoder()
    var tree = SessionTree()
    var issues: [SessionLogIssue] = []
    var version = SessionLog.formatVersion
    private var headerSeen = false
    private var missingHeaderReported = false
    /// Spliced-out compactions, mapped to the parent their children now attach to.
    private var spliced: [EntryID: EntryID?] = [:]

    init(limits: SessionLog.Limits, images: SessionImageStore?) {
        self.limits = limits
        if let images { decoder.userInfo[SessionImageStore.userInfoKey] = images }
    }

    /// The session the lines so far describe, and the repairs they needed.
    var result: RecoveredSession {
        RecoveredSession(tree: SessionMigration.migrated(tree, from: version), issues: issues, formatVersion: version)
    }

    /// Skips line `number`, which is longer than ``SessionLog/Limits/maximumLineBytes``: a reader that streams the file drops it as it
    /// arrives instead of holding it.
    mutating func skipTooLong(number: Int) { issues.append(.lineTooLong(line: number)) }

    mutating func consume(_ line: ArraySlice<UInt8>, number: Int, isFinal: Bool) throws(SessionLogError) {
        guard line.count <= limits.maximumLineBytes else {
            skipTooLong(number: number)
            return
        }
        let record: SessionLogRecord
        do {
            // The one copy at the boundary: the decoder reads a contiguous `[UInt8]`.
            record = try decoder.decode(SessionLogRecord.self, from: Array(line))
        } catch {
            // What a newer ask wrote is kept, not read, and is no damage (ADR-0144); anything else that does not decode is.
            if let kept = newer(line) {
                if let entry = kept { try apply(.entry(entry), line: number) }
                if isFinal { issues.append(.unterminatedFinalLine(line: number)) }
                return
            }
            issues.append(isFinal ? .tornFinalLine(line: number) : .malformedLine(line: number))
            return
        }
        try apply(record, line: number)
        if isFinal { issues.append(.unterminatedFinalLine(line: number)) }
    }

    /// What a line that did not decode is when a newer ask wrote it: a record of a type this build does not have, kept in the tree
    /// (`.some(nil)`), or an entry of a kind it does not have (`.some(entry)`). Nil when it is neither, and so damage.
    private mutating func newer(_ line: ArraySlice<UInt8>) -> SessionEntry?? {
        guard let probe = try? decoder.decode(SessionLogProbe.self, from: Array(line)) else { return nil }
        if !SessionLogRecord.knownTypes.contains(probe.type) {
            tree.keepUnknownRecord(Array(line))
            return .some(nil)
        }
        guard probe.type == "entry", let id = probe.id, let kind = probe.payload?.kind,
            !WirePayload.knownKinds.contains(kind)
        else { return nil }
        return SessionEntry(
            id: EntryID(id),
            parentID: probe.parent.map(EntryID.init),
            payload: .unrecognized(kind: kind, line: Array(line))
        )
    }

    private mutating func apply(_ record: SessionLogRecord, line: Int) throws(SessionLogError) {
        if case .header(let version) = record {
            guard !headerSeen, line == 1 else {
                issues.append(.malformedLine(line: line))
                return
            }
            guard SessionMigration.opens(version) else { throw .unsupportedVersion(version) }
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
            case .thread(let record): tree.recordThread(record)
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
