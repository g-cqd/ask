/// The `ask` executable: argument parsing and the composition root, nothing else.
///
/// Everything with behaviour lives in library targets so it can be tested; this file only binds them.

internal import ArgumentParser
internal import AskCore
internal import AskTUI
internal import Foundation

@main
struct Ask: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "A terminal coding agent: reliable, fast, light.")

    @Flag(help: "Print the four performance budgets as JSON and exit. Read by Scripts/measure-budgets.py.")
    var budgets = false

    func run() throws {
        if budgets {
            FileHandle.standardOutput.write(Data(try Budget.reportJSON()))
            return
        }
        do {
            try runAskTUI()
        } catch {
            // The loop has already restored the terminal by the time an error reaches here.
            FileHandle.standardError.write(Data("ask: \(error)\n".utf8))
            throw ExitCode(70)
        }
    }
}
