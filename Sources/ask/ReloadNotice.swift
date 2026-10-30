internal import AskAgentCore
internal import AskTools
internal import Foundation

/// What a process started by `/reload` knows about the one it replaced.
struct ReloadNotice {
    /// The old build, as ``BinaryIdentity/summary`` described it.
    var from: String
    /// When the reload began, in milliseconds since the epoch.
    var startedMilliseconds: Int
    /// Where the old process wrote what the person allowed for the session (roadmap 0159), read once at start.
    var grantsPath: String?
}

/// What a start says about itself that is not needed to read the conversation: the session it resumed, and the reload that made it (ADR-0119).
func startupDetails(resumed: SessionRecorder?, reloaded: ReloadNotice?) -> [String] {
    var details: [String] = []
    if let resumed { details.append("Resumed session \((resumed.path as NSString).lastPathComponent)") }
    if let reloaded {
        let elapsed = max(0, Int(Date().timeIntervalSince1970 * 1_000) - reloaded.startedMilliseconds)
        details.append(
            "Reloaded ask: \(reloaded.from) → \(BinaryIdentity.running()?.summary ?? "the new build"), in \(elapsed) ms."
        )
    }
    return details
}
