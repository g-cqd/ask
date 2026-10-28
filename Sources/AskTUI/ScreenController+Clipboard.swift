internal import TerminalKitCodecs
internal import TerminalKitInput

/// Copy, cut and paste by Command or Ctrl (roadmap 0082). A terminal that leaves Command+C to the program (with the kitty keyboard
/// protocol, when it has no selection of its own because ask holds the mouse) sends it as the letter with the super modifier, which once
/// typed a "c". The selection handlers copy and cut; this takes what is left: a paste, or a Command chord with nothing to act on.
extension ScreenController {
    /// Whether `key` is Ctrl or Command with `letter`, in either case.
    static func isClipboardChord(_ key: KeyEvent, _ letter: Character) -> Bool {
        guard let lower = letter.lowercased().first?.asciiValue.map(UInt32.init) else { return false }
        if key.keyCode == lower & 0x1F { return true }
        let code = key.keyCode | 0x20
        return code == lower && !key.modifiers.isDisjoint(with: [.ctrl, .super])
    }

    /// Command+V or Ctrl+V pastes the host pasteboard; Command+C or Command+X without a selection does nothing. Nil for any other key.
    /// Ctrl+C and Ctrl+X keep their meanings without a selection (interrupt, clear the draft), so they are not taken here.
    mutating func clipboardChordKey(_ key: KeyEvent) -> [Effect]? {
        if Self.isClipboardChord(key, "v") { return [.pasteFromClipboard] }
        guard key.modifiers.contains(.super) else { return nil }
        return Self.isClipboardChord(key, "c") || Self.isClipboardChord(key, "x") ? [] : nil
    }
}
