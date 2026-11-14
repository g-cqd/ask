/// Decodes server-sent events incrementally, framed per the WHATWG specification.
///
/// Every byte is examined once. A line that arrives whole is parsed in place from the caller's chunk; only a
/// line split across chunks is carried, so the cost does not depend on how the network cut the stream, and
/// neither does what is refused: a line is measured, with its event's data so far, at its end and while it is
/// carried (the fuzzer found a long line that was not `data` passing whole and refused in pieces, roadmap 0232).
/// `id` and `retry` are kept for a stream that is resumed (MCP's streamable HTTP); a provider stream ignores them.
public struct SSEDecoder: Sendable {
    /// Ceilings that keep a hostile or broken stream from growing memory without bound.
    public struct Limits: Sendable, Equatable {
        /// The most bytes one event, or one line, may hold.
        public var maximumEventBytes: Int

        /// Limits with this ceiling.
        public init(maximumEventBytes: Int) { self.maximumEventBytes = maximumEventBytes }

        /// 8 MiB, far above any provider event, low enough to bound a runaway stream.
        public static let standard = Limits(maximumEventBytes: 8 << 20)
    }

    /// Whether the stream ended between events.
    public enum Ending: Sendable, Equatable {
        case complete
        /// Bytes after the last blank line never formed an event. The specification discards them.
        case unterminatedEvent
    }

    private let limits: Limits
    /// The last `id` field's value, the one a resumed stream names in `Last-Event-ID`.
    public private(set) var lastEventID: String?
    /// The last `retry` field's wait, when it was digits only.
    public private(set) var retry: Duration?
    private var carry: [UInt8] = []
    private var name: [UInt8] = []
    private var data: [UInt8] = []
    private var hasData = false
    private var pendingLineFeed = false
    private var atStart = true

    /// A decoder at the start of a stream.
    public init(limits: Limits = .standard) { self.limits = limits }

    /// Decodes `chunk`, appending each completed event to `events`.
    /// - Throws: ``SSEError/eventTooLarge(limit:)``. The decoder must not be fed again after it throws.
    public mutating func feed(_ chunk: Span<UInt8>, into events: inout [SSEEvent]) throws(SSEError) {
        var start = 0
        var index = 0
        if pendingLineFeed, chunk.count > 0 {
            // The previous chunk ended in CR; a LF that opens this one belongs to the same line ending.
            pendingLineFeed = false
            if chunk[0] == .lineFeed { (start, index) = (1, 1) }
        }
        while index < chunk.count {
            let byte = chunk[index]
            if byte == .lineFeed || byte == .carriageReturn {
                try endLine(chunk.extracting(start ..< index), into: &events)
                if byte == .carriageReturn {
                    if index + 1 < chunk.count {
                        if chunk[index + 1] == .lineFeed { index += 1 }
                    } else {
                        pendingLineFeed = true
                    }
                }
                start = index + 1
            }
            index += 1
        }
        guard start < chunk.count else { return }
        guard carry.count + (chunk.count - start) + data.count <= limits.maximumEventBytes else {
            throw .eventTooLarge(limit: limits.maximumEventBytes)
        }
        carry.append(span: chunk.extracting(start ..< chunk.count))
    }

    /// Ends the stream.
    /// - Returns: whether it ended between events.
    public func finish() -> Ending {
        carry.isEmpty && !hasData ? .complete : .unterminatedEvent
    }

    // MARK: - Lines

    private mutating func endLine(_ tail: Span<UInt8>, into events: inout [SSEEvent]) throws(SSEError) {
        if carry.isEmpty {
            try process(tail, into: &events)
            return
        }
        carry.append(span: tail)
        let line = carry
        carry.removeAll(keepingCapacity: true)
        try process(line.span, into: &events)
    }

    private mutating func process(_ raw: Span<UInt8>, into events: inout [SSEEvent]) throws(SSEError) {
        guard raw.count + data.count <= limits.maximumEventBytes else {
            throw .eventTooLarge(limit: limits.maximumEventBytes)
        }
        var line = raw
        if atStart {
            atStart = false
            if line.count >= 3, line[0] == 0xEF, line[1] == 0xBB, line[2] == 0xBF {
                line = line.extracting(3 ..< line.count)
            }
        }
        if line.isEmpty {
            dispatch(into: &events)
            return
        }
        // A comment (`: …`) parses as an empty field name, which matches nothing below.
        var colon = 0
        while colon < line.count, line[colon] != .colon { colon += 1 }
        let field = line.extracting(0 ..< colon)
        var valueStart = Swift.min(colon + 1, line.count)
        if valueStart < line.count, line[valueStart] == .space { valueStart += 1 }
        let value = line.extracting(valueStart ..< line.count)
        if field.matches(.dataField) {
            // Within the limit: the line was, and the value with its line feed is shorter than the line.
            data.append(span: value)
            data.append(.lineFeed)
            hasData = true
        } else if field.matches(.eventField) {
            name.removeAll(keepingCapacity: true)
            name.append(span: value)
        } else if field.matches(.idField) {
            remember(id: value)
        } else if field.matches(.retryField) {
            remember(retry: value)
        }
    }

    /// An `id` with a NUL in it is ignored, as the specification says.
    private mutating func remember(id value: Span<UInt8>) {
        var bytes: [UInt8] = []
        bytes.append(span: value)
        guard !bytes.contains(0) else { return }
        lastEventID = String(decoding: bytes, as: UTF8.self)
    }

    /// A `retry` that is not ASCII digits alone is ignored.
    private mutating func remember(retry value: Span<UInt8>) {
        guard !value.isEmpty, value.count <= 9 else { return }
        var milliseconds = 0
        for offset in 0 ..< value.count {
            let byte = value[offset]
            guard byte >= 0x30, byte <= 0x39 else { return }
            milliseconds = milliseconds * 10 + Int(byte - 0x30)
        }
        retry = .milliseconds(milliseconds)
    }

    private mutating func dispatch(into events: inout [SSEEvent]) {
        defer {
            name.removeAll(keepingCapacity: true)
            data.removeAll(keepingCapacity: true)
            hasData = false
        }
        guard hasData else { return }
        data.removeLast()
        events.append(SSEEvent(name: name.isEmpty ? "message" : String(decoding: name, as: UTF8.self), data: data))
    }
}

extension UInt8 {
    fileprivate static let lineFeed: UInt8 = 0x0A
    fileprivate static let carriageReturn: UInt8 = 0x0D
    fileprivate static let colon: UInt8 = 0x3A
    fileprivate static let space: UInt8 = 0x20
}

extension [UInt8] {
    fileprivate static let dataField = Array("data".utf8)
    fileprivate static let eventField = Array("event".utf8)
    fileprivate static let idField = Array("id".utf8)
    fileprivate static let retryField = Array("retry".utf8)
}

extension Span<UInt8> {
    fileprivate func matches(_ bytes: [UInt8]) -> Bool {
        guard count == bytes.count else { return false }
        for offset in 0 ..< count where self[offset] != bytes[offset] { return false }
        return true
    }
}

extension [UInt8] {
    fileprivate mutating func append(span: Span<UInt8>) {
        reserveCapacity(count + span.count)
        for index in 0 ..< span.count { append(span[index]) }
    }
}
