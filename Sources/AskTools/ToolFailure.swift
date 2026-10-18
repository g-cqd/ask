internal import AskAI
public import AskAgentCore
internal import Foundation

/// An error output as a value that can travel in a `Result`.
struct ToolFailure: Error {
    let output: ToolOutput
    init(_ message: String) { output = .error(message) }
}
