internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The status bar's git segment kept current (roadmap 0186): read off the screen's thread at the start, after a tool call and when a
/// run ends. One read at a time: a request while one runs asks for one more after it, so a burst of tool calls is two reads, not many.
final class GitStatusRefresh: Sendable {
    private let state = Mutex((running: false, again: false))

    func request(in directory: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let starts = state.withLock { state in
            if state.running { state.again = true }
            defer { state.running = true }
            return !state.running
        }
        guard starts else { return }
        let path = LaunchEnvironment.values["PATH"]
        Task.detached(priority: .utility) {
            repeat {
                update(.gitStatus(await GitStatus.read(in: directory, path: path)))
            } while self.state.withLock { state in
                defer { state.again = false }
                if !state.again { state.running = false }
                return state.again
            }
        }
    }
}
