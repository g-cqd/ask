internal import TerminalKitCodecs
internal import TerminalKitInput

extension PromptEditor {
    /// Whether `key` backs over text: Backspace or Ctrl-H, and Ctrl-D, which deletes forward.
    static func isDeletion(_ key: KeyEvent) -> Bool {
        let code = key.keyCode
        if key.modifiers.contains(.ctrl), let scalar = Unicode.Scalar(code), scalar.isASCII {
            return [0x04, 0x08].contains(scalar.value & 0x1F)
        }
        return code == 0x7F || code == 0x08 || code == 0x04
    }

    /// Whether `key` puts text in the draft: a character, a newline by Shift-Enter or Ctrl-J, but not a control or a function key.
    /// This is the editor's own rule, so a selection is replaced by exactly the keys that would have typed something.
    static func insertsText(_ key: KeyEvent) -> Bool {
        let code = key.keyCode
        if code == 0x0D, key.modifiers.contains(.shift) { return true }
        if key.modifiers.contains(.ctrl), let scalar = Unicode.Scalar(code), scalar.isASCII {
            return scalar.value & 0x1F == 0x0A
        }
        guard code >= 0x20, code != 0x7F, !(0xE000 ... 0xF8FF).contains(code) else { return code == 0x0A }
        return !key.associatedText.isEmpty || Unicode.Scalar(code) != nil
    }
}
