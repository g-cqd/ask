internal import Synchronization

@testable import AskTUI

/// Stands in for the host pasteboard and for the screen's loop: records what the pasteboard was asked to hold, answers with a result
/// the test chose, and lets a test wait for the final notice a copy reports later.
// SAFETY: every access goes through a mutex or the stream, so the class has no unsynchronised state.
final class ClipboardRecorder: @unchecked Sendable {
    private let copied = Mutex<[String]>([])
    private let answer: PasteboardResult
    private let results: AsyncStream<(notice: String, failed: Bool)>
    private let report: AsyncStream<(notice: String, failed: Bool)>.Continuation

    init(answering answer: PasteboardResult = .copied) {
        self.answer = answer
        (results, report) = AsyncStream.makeStream()
    }

    var texts: [String] { copied.withLock { $0 } }

    /// The pasteboard to give a `ScreenClipboard`.
    var pasteboard: @Sendable (String) async -> PasteboardResult {
        { [self] text in
            copied.withLock { $0.append(text) }
            return answer
        }
    }

    /// Copies `text` and waits for the final notice, for a copy that goes to the pasteboard.
    func copy(_ clipboard: inout ScreenClipboard, _ text: String) async -> (
        initial: String, final: (notice: String, failed: Bool)?
    ) {
        let report = report
        let initial = clipboard.copy(text) { report.yield(($0, $1)) }
        var iterator = results.makeAsyncIterator()
        return (initial, await iterator.next())
    }
}
