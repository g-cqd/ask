internal import AskAgentCore
internal import AskTUI
internal import Foundation

/// Runs `screen` with standard error kept in `stderr.log` (``StandardErrorGuard``): the screen is drawn on the terminal standard error
/// also is, so what a library prints there would land on the conversation. The terminal is given back as soon as the screen closes,
/// before anything else is said and before a reload starts the new build; when something was written meanwhile, where it is kept is
/// said once.
func keepingStandardErrorOffTheScreen<Result>(_ screen: () async throws -> Result) async rethrows -> Result {
    let path = SessionDirectory.stateRoot(environment: LaunchEnvironment.values) + "/stderr.log"
    let quiet = StandardErrorGuard(logPath: path)
    defer {
        if let written = quiet?.end(), written > 0 {
            FileHandle.standardError.write(
                Data(
                    "ask: \(written) bytes were written to standard error while the screen was open; they are in \(path)\n"
                        .utf8
                )
            )
        }
    }
    return try await screen()
}
