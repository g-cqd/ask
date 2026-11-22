internal import Darwin

/// An immutable archive entry. Parents must precede children in archive order.
///
/// Its payload is held, or, for an entry opening a session found nothing is reading (roadmap 0238), left in the session file and read
/// from it when asked: through ``payload`` either way. What a scan over every entry needs, its ``kind``, is always held.
public struct SessionEntry: Sendable, Equatable {
    /// Which of a payload's cases an entry holds, readable without reading the payload.
    public enum Kind: Sendable, Equatable {
        case destination, user, assistant, response, toolResult, compaction, unrecognized
    }

    /// What an entry holds: the payload, or where its record is.
    private enum Content: Sendable {
        case held(SessionPayload)
        case inFile(ColdLine)
    }

    /// Stable archive identifier.
    public let id: EntryID
    /// An earlier archive entry, or nil for a root.
    public let parentID: EntryID?
    /// Which case the payload is.
    public let kind: Kind
    /// When the entry was recorded, in milliseconds since 1970 (roadmap 0239): what a turn's or a task's time is read from. Nil for an
    /// entry an older ask wrote. Not part of equality: two entries are the same conversation whenever they were written.
    public let recordedAt: Int?
    private let content: Content

    /// What shows where a payload left in the file cannot be read back (the file was changed or truncated under the session).
    static let unreadableNote = "[this entry could not be read from the session file]"

    /// The content of this entry. One left in the file is read from it, and shows ``unreadableNote`` when the file no longer has
    /// it: ``readablePayload`` says which.
    public var payload: SessionPayload { readablePayload ?? .assistant(Self.unreadableNote) }

    /// The content of this entry, or nil when it was left in the file and the file no longer has it as it was.
    public var readablePayload: SessionPayload? {
        switch content {
            case .held(let payload): payload
            case .inFile(let line): line.payload()
        }
    }

    /// Whether the payload is left in the file.
    var isInFile: Bool {
        if case .inFile = content { return true }
        return false
    }

    /// Builds an entry for archive restoration; the tree validates identifiers and ancestry.
    /// - Parameters:
    ///   - id: identifier unique in the archive.
    ///   - parentID: an earlier entry, or nil.
    ///   - payload: message or compaction content.
    ///   - recordedAt: when it was recorded, in milliseconds since 1970, or nil when that is not known.
    public init(id: EntryID, parentID: EntryID?, payload: SessionPayload, recordedAt: Int? = nil) {
        self.id = id
        self.parentID = parentID
        kind = payload.kind
        self.recordedAt = recordedAt
        content = .held(payload)
    }

    private init(_ entry: SessionEntry, content: Content, parent: EntryID?) {
        id = entry.id
        parentID = parent
        kind = entry.kind
        recordedAt = entry.recordedAt
        self.content = content
    }

    /// Now, in milliseconds since 1970, as ``recordedAt`` holds it.
    static func now() -> Int {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return time.tv_sec * 1_000 + time.tv_nsec / 1_000_000
    }

    /// This entry with its payload left in the file, at `line`, or itself when that saves nothing: a prompt (a branch picker lists
    /// them), a destination or a compaction (small, and read at every request), a payload with pictures, a short record.
    /// - Parameters:
    ///   - source: the file, open.
    ///   - offset: where the record starts.
    ///   - line: the record, whole, which the entry was decoded from.
    /// - Returns: the entry that holds where its record is, or this one.
    func leavingInFile(of source: ColdSource, at offset: Int, line: ArraySlice<UInt8>) -> SessionEntry {
        guard case .held = content, line.count >= ColdLine.smallest else { return self }
        switch kind {
            case .destination, .compaction, .unrecognized, .user: return self
            case .toolResult, .assistant, .response: break
        }
        // Pictures are read from the image store when an entry is decoded, and said to be lost then: where they are, that is now.
        guard !Self.namesPictures(line) else { return self }
        let cold = ColdLine(source: source, offset: offset, length: line.count)
        return SessionEntry(self, content: .inFile(cold), parent: parentID)
    }

    /// Whether `line` has an `"images"` key: a scan of bytes, since a generic search of a long line is what a session of them waits on.
    private static func namesPictures(_ line: ArraySlice<UInt8>) -> Bool {
        let key = Array("\"images\"".utf8)
        return line.withUnsafeBytes { bytes in
            guard let start = bytes.baseAddress else { return false }
            return unsafe memmem(start, bytes.count, key, key.count) != nil
        }
    }

    /// This entry with its payload held, read from the file when it was left there; nil when the file no longer has it.
    func holding() -> SessionEntry? {
        guard case .inFile = content else { return self }
        guard let payload = readablePayload else { return nil }
        return SessionEntry(id: id, parentID: parentID, payload: payload, recordedAt: recordedAt)
    }

    /// This entry under another parent, the payload as it was: a repair of a session's ancestry is no reason to read one.
    func reparented(to parent: EntryID?) -> SessionEntry { SessionEntry(self, content: content, parent: parent) }

    public static func == (left: SessionEntry, right: SessionEntry) -> Bool {
        left.id == right.id && left.parentID == right.parentID && left.kind == right.kind
            && left.payload == right.payload
    }
}
