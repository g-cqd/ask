/// What a terminal byte stream prints, for checking what a viewer was shown (ADR-0170): its text, with escape sequences left out.
package enum TerminalOutput {
    /// `bytes` without CSI and OSC sequences or other escapes; the characters a terminal would draw, in the order they were sent.
    package static func printed(_ text: String) -> String {
        var out = ""
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1B}" else {
                out.unicodeScalars.append(scalar)
                continue
            }
            switch scalars.next() {
                case "[":
                    // CSI: parameters and intermediates up to a final byte in @ to ~.
                    while let next = scalars.next(), !(0x40 ... 0x7E).contains(next.value) {}
                case "]":
                    // OSC: up to BEL or ESC \.
                    while let next = scalars.next(), next != "\u{07}" {
                        if next == "\u{1B}" {
                            _ = scalars.next()
                            break
                        }
                    }
                default: continue
            }
        }
        return out
    }

    /// Whether `text`'s characters appear in order in what `stream` prints. Spaces are not looked for: a space drawn over a blank
    /// cell changes nothing, so a frame of differences never writes it.
    package static func shows(_ text: String, in stream: String) -> Bool {
        var wanted = text.filter { $0 != " " }.makeIterator()
        var next = wanted.next()
        for character in printed(stream) where character == next { next = wanted.next() }
        return next == nil
    }
}
