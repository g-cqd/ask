/// The `ask` executable.
///
/// A thin entry point. Everything lives in the library targets so it can be tested, and so this file
/// stays small enough to prove it cannot slow anything down.
///
/// `--budgets` prints the four budgets as JSON so the measurement harness reads them from the one
/// place that defines them, rather than keeping a second copy of the numbers in a script that can
/// drift.

internal import AskCore
internal import AskTUI
internal import Foundation

@main
struct Ask {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "--budgets" {
            print(budgetsJSON)
            return
        }

        do {
            try runAskTUI()
        } catch {
            // A terminal program that fails to start still has to leave the terminal usable, so the
            // teardown ladder runs before anything is printed.
            FileHandle.standardError.write(Data("ask: \(error)\n".utf8))
            exit(70)
        }
    }

    /// The budgets, as JSON, for `Scripts/measure-budgets.py`.
    static var budgetsJSON: String {
        """
        {
          "coldStartMilliseconds": \(Budget.coldStartMilliseconds),
          "idleMemoryMebibytes": \(Budget.idleMemoryMebibytes),
          "inputDelayMilliseconds": \(Budget.inputDelayMilliseconds),
          "actionToActionMilliseconds": \(Budget.actionToActionMilliseconds)
        }
        """
    }
}
