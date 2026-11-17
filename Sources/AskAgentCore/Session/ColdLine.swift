internal import AemiJSON

/// Where an entry's record is in the session file, in place of its payload (roadmap 0238): a long session's tool results and
/// responses are most of its memory, and a request, the screen and a rewind read the few at its end.
struct ColdLine: Sendable {
    /// The least a line must be, in bytes, to be left in the file; under it the entry costs no more than its place.
    static let smallest = 512

    private let source: ColdSource
    private let offset: Int
    private let length: Int

    init(source: ColdSource, offset: Int, length: Int) {
        self.source = source
        self.offset = offset
        self.length = length
    }

    /// The payload of the record, read from the file and decoded again, or nil when the file no longer has it as it was.
    func payload() -> SessionPayload? {
        guard
            let line = source.read(offset: offset, length: length),
            let record = try? AemiJSON.JSONDecoder().decode(SessionLogRecord.self, from: line),
            case .entry(let entry) = record
        else { return nil }
        return entry.payload
    }
}
