/// The mouse pointer's shape over the screen (OSC 22, note n13): a hand over what a click acts on, the terminal's own elsewhere.
enum PointerShape: String, Sendable, Equatable {
    case `default`
    case pointer

    /// The sequence that sets it: `ESC ] 22 ; name ST`, the CSS cursor names kitty, Ghostty and foot read; others ignore it.
    var sequence: [UInt8] { Array("\u{1B}]22;\(rawValue)\u{1B}\\".utf8) }
}
