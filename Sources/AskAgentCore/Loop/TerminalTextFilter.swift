/// Text from the model or a tool, made safe to write to a terminal (roadmap 0153, finding 5): every escape sequence is removed whole
/// (CSI, OSC such as the clipboard's OSC 52, DCS, SOS, PM, APC, two-byte escapes, and their 8-bit forms), and every other control but
/// tab and line feed is dropped, a carriage return included. It keeps its state between pieces, so a sequence split across two streamed
/// deltas is still removed whole; a line feed, or a sequence longer than any real one, ends a sequence, so one that never ends cannot
/// hide the rest of the text.
struct TerminalTextFilter: Sendable {
    private enum State: Sendable {
        case text
        /// After ESC, and after any intermediate bytes.
        case escape
        /// A CSI's parameters, until its final byte.
        case control
        /// An OSC, DCS, SOS, PM or APC's contents, until BEL or ST.
        case string
        /// ESC inside a string: a backslash makes it ST.
        case stringEscape
    }

    private var state = State.text
    /// Scalars consumed by the sequence in progress.
    private var length = 0
    /// The most scalars a sequence may take before it is given up and the text after it shown.
    private static let longest = 4_096

    /// `text` without what the terminal would act on.
    mutating func filter(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars { step(scalar, into: &kept) }
        return String(kept)
    }

    /// `text` filtered alone: for a line said whole.
    static func filtered(_ text: String) -> String {
        var filter = TerminalTextFilter()
        return filter.filter(text)
    }

    private mutating func step(_ scalar: Unicode.Scalar, into kept: inout String.UnicodeScalarView) {
        let value = scalar.value
        if state != .text {
            // A line end, or a sequence longer than any real one, gives the sequence up: the text goes on.
            length += 1
            if value == 0x0A || length > Self.longest {
                state = .text
                if value == 0x0A { kept.append(scalar) }
                return
            }
        }
        switch state {
            case .text: text(scalar, into: &kept)
            case .escape:
                switch value {
                    case 0x5B: begin(.control)  // [
                    case 0x5D, 0x50, 0x58, 0x5E, 0x5F: begin(.string)  // ] P X ^ _
                    case 0x20 ... 0x2F: break  // an intermediate byte: the final one follows
                    default: state = .text  // the final byte of a two-byte escape
                }
            case .control:
                if (0x40 ... 0x7E).contains(value) { state = .text }
            case .string:
                if value == 0x07 || value == 0x9C { state = .text }
                if value == 0x1B { state = .stringEscape }
            case .stringEscape:
                state = value == 0x5C ? .text : .string
        }
    }

    private mutating func text(_ scalar: Unicode.Scalar, into kept: inout String.UnicodeScalarView) {
        switch scalar.value {
            case 0x09, 0x0A: kept.append(scalar)
            case 0x1B: begin(.escape)
            case 0x9B: begin(.control)
            case 0x90, 0x98, 0x9D, 0x9E, 0x9F: begin(.string)
            case 0x00 ..< 0x20, 0x7F ... 0x9F: break
            default: kept.append(scalar)
        }
    }

    private mutating func begin(_ next: State) {
        state = next
        length = 0
    }
}
