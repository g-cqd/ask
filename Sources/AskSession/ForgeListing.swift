internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The workspace's open pull requests and issues for the `#` picker, and its branch's pull request for the status bar (roadmap 0186):
/// read off the screen's thread at the start and, at most every five minutes, when a run ends, so an unauthenticated person stays well
/// within GitHub's 60 requests an hour. The picker is told its list is stale when a read lands.
final class ForgeListing: Sendable {
    static let interval: Duration = .seconds(300)
    private let refresh = CoalescedRefresh()
    private let state = Mutex<(rows: [ChoiceRow], read: ContinuousClock.Instant?)>(([], nil))

    /// The open pull requests and issues, as `#` picker rows.
    var rows: [ChoiceRow] { state.withLock { $0.rows } }

    func request(in workspace: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let due = state.withLock { state in state.read.map { .now - $0 >= Self.interval } ?? true }
        guard due else { return }
        state.withLock { $0.read = .now }
        refresh.request { [self] in
            let token = LaunchEnvironment.values["GITHUB_TOKEN"]
            let path = LaunchEnvironment.values["PATH"]
            let open = await ForgeReader.openItems(workspace: workspace, token: token, path: path)
            state.withLock { $0.rows = open.map(Self.row) }
            update(.choicesStale(command: "#"))
            let branch = await ForgeReader.currentBranch(workspace: workspace, path: path)
            let pull = await ForgeReader.branchPullRequest(
                branch: branch ?? "",
                workspace: workspace,
                token: token,
                path: path
            )
            update(.branchPullRequest(pull))
        }
    }

    private static func row(_ item: ForgeReferences.Item) -> ChoiceRow {
        ChoiceRow(label: "#\(item.number)", detail: "\(item.kind) · \(item.title)", arguments: "#\(item.number)")
    }
}
