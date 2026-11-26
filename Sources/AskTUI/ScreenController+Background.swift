internal import TerminalKitCodecs
internal import TerminalKitInput

/// Roadmap 0173: the person sends the command the model waits on to the background. Ctrl+B, which every terminal sends, and Ctrl+Enter
/// where the terminal reports it; only while a command block runs, or a `job` call waits (owner, 2026-11-26), in what is shown: main's
/// turn, or in a thread's lane that thread's. Ctrl+B keeps moving the cursor otherwise.
extension ScreenController {
    mutating func backgroundKey(_ key: KeyEvent) -> [Effect]? {
        let ctrlB =
            key.keyCode == 0x02 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x62 || key.keyCode == 0x42))
        let ctrlEnter = key.keyCode == Key.enter.rawValue && key.modifiers.contains(.ctrl)
        guard ctrlB || ctrlEnter, ScreenComposer.focusedWorks(state), state.transcript.hasRunningWait else {
            return nil
        }
        if let lane = state.lane, lane.isThread { return [.sendThreadCommandToBackground(id: lane.id)] }
        return [.sendCommandToBackground]
    }

    /// Stops what is shown working: main's turn, or in a thread's lane that thread with the threads under it (roadmap 0195).
    mutating func stopFocused() -> [Effect] {
        if let lane = state.lane, lane.isThread {
            state.transcript.addNotice("Stopping \(lane.name) and the threads under it…", isError: false)
            return [.stopThread(id: lane.id)]
        }
        return abort()
    }
}
