@testable import AskAgentCore

/// A session file (`SessionLog.recover`, `FramedReader`): bytes from disk, possibly damaged or written by someone else. Promised
/// (ADR-0013): whatever the bytes, recovery returns a valid tree and the repairs it made, or one of its two refusals; it never traps.
/// Recovering the same bytes twice gives the same result.
let fuzzSession: @Sendable ([UInt8]) -> Void = { bytes in
    let limits = SessionLog.Limits.standard
    let first = try? SessionLog.recover(bytes, limits: limits)
    let second = try? SessionLog.recover(bytes, limits: limits)
    if first?.tree.entries.count != second?.tree.entries.count || first?.issues.count != second?.issues.count {
        broken("session: recovering the same bytes twice differed")
    }
    if let tree = first?.tree {
        // The tree it returns is one the rest of ask can walk.
        _ = tree.context()
        _ = RequestContext(tree.context()).messages
    }
    _ = try? FramedReader.read(bytes, key: nil)
}
