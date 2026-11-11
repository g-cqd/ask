internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The person's own `!` and `!!` commands (note n56; the owner's answers of 2026-11-11): run at once, beside any turn, in their login
/// shell, under the session's sandbox, without asking. The result goes with their next message, or, for `!!`, is sent at once.
extension AgentConversation {
    func shell(_ command: String, sends: Bool, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<
        Void, Never
    > {
        let settings = current.withLock { $0.settings }
        let narrowed = narrowing.policy
        let jobs = jobs
        return Task {
            let id = "person-" + UUID().uuidString
            update(
                .toolStarted(
                    name: "!",
                    summary: "",
                    id: id,
                    fullInput: command,
                    command: ToolCommand(yield: .seconds(BashTool.personYield))
                )
            )
            let context = ToolContext(
                workingDirectory: settings.workspace,
                outputDirectory: SessionDirectory(project: settings.workspace, environment: LaunchEnvironment.values)
                    .path
                    + "/output",
                sandbox: narrowed.map { settings.sandbox.intersecting($0) } ?? settings.sandbox,
                commandEnvironment: settings.commandEnvironment
            )
            let output = await BashTool(jobs: jobs, commandEnvironment: settings.commandEnvironment)
                .runForPerson(command, shell: LaunchEnvironment.values["SHELL"], in: context)
            update(
                .toolFinished(
                    output.isError ? .failed(TextLines.last(of: output.content) ?? "") : .succeeded,
                    output: output.content,
                    id: id,
                    backgroundJob: output.backgroundJob
                )
            )
            let report = ShellReport.text(command: command, output: output.content, job: output.backgroundJob)
            if sends {
                update(.submitPrompt(report))
            } else {
                shellReports.withLock { $0.append(report) }
            }
        }
    }

    /// `text` after the results of the `!` commands run since the last message, which go with it once.
    func attachingShellReports(_ text: String) -> String {
        let reports = shellReports.withLock { reports in
            defer { reports.removeAll() }
            return reports
        }
        return reports.isEmpty ? text : reports.joined(separator: "\n") + "\n" + text
    }
}
