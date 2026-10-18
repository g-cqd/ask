/// The `ask` executable.
///
/// A thin entry point. Everything lives in the library targets so it can be tested, and so this file
/// stays small enough to prove it cannot slow anything down.

internal import AskTUI
internal import Foundation

@main
struct Ask {
    static func main() {
        do {
            try runAskTUI()
        } catch {
            // A terminal program that fails to start still has to leave the terminal usable, so the
            // teardown ladder runs before anything is printed.
            FileHandle.standardError.write(Data("ask: \(error)\n".utf8))
            exit(70)
        }
    }
}
