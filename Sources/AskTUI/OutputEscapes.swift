internal import TerminalKitStyle

/// A tool's output with its terminal escapes read (note n30). SGR's colours and text attributes, and OSC 8 links ask accepts, become
/// spans over the plain text. Everything else a program writes is removed whole: cursor moves, clears, titles, the clipboard's OSC 52,
/// DCS, SOS, PM and APC strings, two-byte escapes, their 8-bit forms, and every control but tab, line feed and carriage return. Nothing
/// of it reaches the terminal raw, and the text copied or folded is the plain one.
///
/// Bounded like ``TerminalTextFilter``: a line feed, or a sequence longer than any real one, ends a sequence, so one that never ends
/// cannot hide the rest of the output. A background colour is not kept, so the block's own shows.
struct OutputEscapes: Sendable, Equatable {
    /// A run of one line's bytes, in the plain text, drawn in a style of its own; its `link` is an OSC 8 target ask accepts.
    struct Span: Sendable, Equatable {
        var bytes: Range<Int>
        var style: Style
    }

    /// The output without any escape or control but tab, line feed and carriage return.
    var text: String
    /// Each hard line's spans, by line; empty when the output had no escape at all.
    var lines: [[Span]]

    /// The most bytes a sequence may take before it is given up and the text after it shown.
    static let longest = 4_096

    init(_ raw: String) {
        // Most output has no escape: it is kept as it is, unread.
        guard Self.needsReading(raw) else {
            text = raw
            lines = []
            return
        }
        var reader = Reader()
        for byte in raw.utf8 { reader.step(byte) }
        reader.endLine()
        text = String(decoding: reader.kept, as: UTF8.self)
        lines = reader.lines
    }

    /// Whether `raw` holds an escape, a C1 lead byte, or a control but tab, line feed and carriage return. One pass over the bytes
    /// in place: two through `String.UTF8View`, a byte at a time, were a sixth of a long session's resume (t233).
    static func needsReading(_ raw: String) -> Bool {
        var raw = raw
        return raw.withUTF8 { bytes in
            bytes.contains { byte in
                byte == 0x1B || byte == 0xC2 || byte == 0x7F
                    || (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D)
            }
        }
    }

    private struct Reader {
        enum State {
            case text, escape, control, string, stringEscape, osc, oscEscape
            /// After 0xC2 in text: a C1 control follows, or the second byte of a printable character.
            case lead
        }

        var state = State.text
        var kept: [UInt8] = []
        var lines: [[Span]] = []
        private var spans: [Span] = []
        /// The current line's first byte in `kept`, and where the current style's run began.
        private var lineStart = 0
        private var runStart = 0
        private var style = Style()
        private var sequence: [UInt8] = []

        mutating func step(_ byte: UInt8) {
            if state != .text, state != .lead, givesUp(byte) { return }
            switch state {
                case .text: text(byte)
                case .lead:
                    state = .text
                    if (0x80 ... 0x9F).contains(byte) { c1(byte) } else { kept += [0xC2, byte] }
                case .escape: escape(byte)
                case .control:
                    if (0x40 ... 0x7E).contains(byte) {
                        state = .text
                        if byte == 0x6D { apply(sgr: sequence.dropLast()) }  // m
                    }
                case .string, .stringEscape: string(byte)
                case .osc, .oscEscape: osc(byte)
            }
        }

        /// Inside a sequence: a line feed, or one byte past the longest, gives it up and the text goes on; any other byte is kept in it.
        private mutating func givesUp(_ byte: UInt8) -> Bool {
            guard byte == 0x0A || sequence.count > OutputEscapes.longest else {
                sequence.append(byte)
                return false
            }
            state = .text
            sequence.removeAll(keepingCapacity: true)
            if byte == 0x0A { text(byte) }
            return true
        }

        /// After ESC: the introducer of a longer sequence, an intermediate byte, or the final byte of a two-byte escape.
        private mutating func escape(_ byte: UInt8) {
            switch byte {
                case 0x5B: begin(.control)  // [
                case 0x5D: begin(.osc)  // ]
                case 0x50, 0x58, 0x5E, 0x5F: begin(.string)  // P X ^ _
                case 0x20 ... 0x2F: break
                default: state = .text
            }
        }

        /// A DCS, SOS, PM or APC string, dropped up to BEL or ST.
        private mutating func string(_ byte: UInt8) {
            if state == .stringEscape {
                state = byte == 0x5C ? .text : .string
                return
            }
            if byte == 0x07 || endsWithST { state = .text }
            if byte == 0x1B { state = .stringEscape }
        }

        /// An OSC, read up to BEL or ST.
        private mutating func osc(_ byte: UInt8) {
            if state == .oscEscape {
                if byte == 0x5C { endOSC(sequence.dropLast(2)) } else { state = .osc }
                return
            }
            if byte == 0x07 { endOSC(sequence.dropLast()) }
            if endsWithST { endOSC(sequence.dropLast(2)) }
            if byte == 0x1B { state = .oscEscape }
        }

        /// Whether the sequence has just read the 8-bit string terminator, U+009C.
        private var endsWithST: Bool { sequence.count >= 2 && sequence.suffix(2).elementsEqual([0xC2, 0x9C]) }

        private mutating func text(_ byte: UInt8) {
            switch byte {
                case 0x0A:
                    endLine()
                    kept.append(byte)
                    lineStart = kept.count
                    runStart = kept.count
                case 0x09, 0x0D: kept.append(byte)
                case 0x1B: begin(.escape)
                case 0xC2: state = .lead
                case 0x00 ..< 0x20, 0x7F: break
                default: kept.append(byte)
            }
        }

        /// An 8-bit control: CSI, OSC and the string introducers begin their sequences, ST and the rest are dropped.
        private mutating func c1(_ byte: UInt8) {
            switch byte {
                case 0x9B: begin(.control)
                case 0x9D: begin(.osc)
                case 0x90, 0x98, 0x9E, 0x9F: begin(.string)
                default: break
            }
        }

        private mutating func begin(_ next: State) {
            state = next
            sequence.removeAll(keepingCapacity: true)
        }

        /// Ends the current line's run and keeps its spans; the style goes on to the next line.
        mutating func endLine() {
            closeRun()
            lines.append(spans)
            spans.removeAll()
        }

        private mutating func closeRun() {
            if runStart < kept.count, style != Style() {
                spans.append(Span(bytes: runStart - lineStart ..< kept.count - lineStart, style: style))
            }
            runStart = kept.count
        }

        private mutating func change(to next: Style) {
            guard next != style else { return }
            closeRun()
            style = next
        }

        private mutating func apply(sgr parameters: ArraySlice<UInt8>) {
            guard let next = OutputEscapes.styled(style, sgr: parameters) else { return }
            change(to: next)
        }

        /// An OSC: `8;params;URI` starts a link ask accepts, or ends one; any other is dropped.
        private mutating func endOSC(_ content: ArraySlice<UInt8>) {
            state = .text
            guard content.starts(with: [0x38, 0x3B]) else { return }  // 8;
            let rest = content.dropFirst(2)
            guard let separator = rest.firstIndex(of: 0x3B) else { return }
            var next = style
            next.link = OutputEscapes.acceptedLink(String(decoding: rest[(separator + 1)...], as: UTF8.self))
            change(to: next)
        }
    }

    /// `uri` if ask opens links like it, by its own rule (``LinkOpener``): http, https, file or mailto, and safe to write; nil otherwise.
    static func acceptedLink(_ uri: String) -> String? {
        guard uri.utf8.count <= 2_048, Style.isSafeLink(uri) else { return nil }
        let lower = uri.lowercased()
        let schemes = ["http://", "https://", "file://", "mailto:"]
        return schemes.contains { lower.hasPrefix($0) } ? uri : nil
    }
}
