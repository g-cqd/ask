internal import AskAgentCore

/// What the `tasks` and `ideas` tools share (ADR-0140): no list before the session's is open, and a refused change told in words.
enum ListToolRun {
    static func run<Refusal: Error>(
        attached: Bool,
        missing: String,
        refusal: Refusal.Type,
        words: (Refusal) -> String,
        _ body: () throws -> ToolOutput
    ) throws(ToolFailure) -> ToolOutput {
        guard attached else { throw ToolFailure(missing) }
        do {
            return try body()
        } catch let error as Refusal {
            throw ToolFailure(words(error))
        } catch let error as ToolFailure {
            throw error
        } catch {
            throw ToolFailure("The list could not be read or changed: \(error)")
        }
    }
}
