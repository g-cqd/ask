internal import TerminalKitCodecs
internal import TerminalKitInput

/// Roadmap 0173: the person sends the command the model waits on to the background. Ctrl+B, which every terminal sends, and Ctrl+Enter
/// where the terminal reports it; only while a command block runs, so Ctrl+B keeps moving the cursor otherwise.
extension ScreenController {
    mutating func backgroundKey(_ key: KeyEvent) -> [Effect]? {
        guard state.running, state.transcript.hasRunningCommand else { return nil }
        let ctrlB =
            key.keyCode == 0x02 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x62 || key.keyCode == 0x42))
        let ctrlEnter = key.keyCode == Key.enter.rawValue && key.modifiers.contains(.ctrl)
        return ctrlB || ctrlEnter ? [.sendCommandToBackground] : nil
    }
}
