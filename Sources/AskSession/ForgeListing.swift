internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The workspace's open pull requests and issues for the `#` picker, and its branch's pull request for the status bar (roadmap 0186):
/// read off the screen's thread at the start and, at most every five minutes, when a run ends, so an unauthenticated person stays well
/// within GitHub's 60 requests an hour. The picker is told its list is stale when a read lands.
///
/// The read is a child's (ADR-0152): this ask run again as `ask forge`, which asks GitHub, prints what it found and ends, so the
/// network stack a request loads is never an idle ask's.
final class ForgeListing: Sendable {
    /// Reads a workspace's snapshot; nothing found is an empty one.
    typealias Read = @Sendable (_ workspace: String) async -> ForgeSnapshot

    static let interval: Duration = .seconds(300)
    private let refresh = CoalescedRefresh()
    private let state = Mutex<(rows: [ChoiceRow], read: ContinuousClock.Instant?)>(([], nil))
    private let read: Read

    /// A listing read by `read`: by a child of the running executable unless a test says otherwise.
    init(read: @escaping Read = ForgeListing.inChild) { self.read = read }

    /// The open pull requests and issues, as `#` picker rows.
    var rows: [ChoiceRow] { state.withLock { $0.rows } }

    func request(in workspace: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let due = state.withLock { state in
            guard Self.isDue(lastRead: state.read, now: .now) else { return false }
            state.read = .now
            return true
        }
        guard due else { return }
        refresh.request { [self] in
            let snapshot = await read(workspace)
            state.withLock { $0.rows = snapshot.open.map(Self.row) }
            update(.choicesStale(command: "#"))
            update(.branchPullRequest(snapshot.pullRequest))
        }
    }

    /// Whether a read is due: the first, and one ``interval`` after the last.
    static func isDue(lastRead: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        lastRead.map { now - $0 >= interval } ?? true
    }

    /// The snapshot from a child of the running executable, with the person's `GITHUB_TOKEN` when they set one.
    static let inChild: Read = { workspace in
        let values = LaunchEnvironment.values
        guard let executable = BinaryIdentity.running()?.path else { return ForgeSnapshot() }
        let read = await ForgeSnapshot.read(
            by: executable,
            workspace: workspace,
            token: values["GITHUB_TOKEN"],
            path: values["PATH"]
        )
        return read ?? ForgeSnapshot()
    }

    private static func row(_ entry: ForgeSnapshot.Entry) -> ChoiceRow {
        ChoiceRow(label: "#\(entry.number)", detail: "\(entry.kind) · \(entry.title)", arguments: "#\(entry.number)")
    }
}
