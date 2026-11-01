internal import AskAgentCore

/// What the `tasks` and `ideas` tools share (ADR-0141): no list before the session's is open; the changes planned and kept under the
/// list's lock, then the read; every refusal said in words.
enum ListToolRun {
    static func run<List: ChangeList>(
        _ board: ChangeBoard<List>,
        missing: String,
        plan: ((List) throws -> (change: List.Change?, answer: String))?,
        read: ((List) throws -> String)?
    ) throws(ToolFailure) -> ToolOutput {
        guard board.isAttached else { throw ToolFailure(missing) }
        do {
            var parts: [String] = []
            if let plan { parts.append(try board.update(plan)?.answer ?? "") }
            if let read, let list = try board.current() { parts.append(try read(list)) }
            return ToolOutput(parts.joined(separator: "\n\n"))
        } catch let refusal as ListPlanError {
            throw ToolFailure(refusal.words)
        } catch is ListRecordError {
            throw ToolFailure("This list was written by a newer ask: it can be read here, not changed.")
        } catch {
            throw ToolFailure("The list could not be read or changed: \(error)")
        }
    }
}
