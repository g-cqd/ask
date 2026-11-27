internal import TerminalKitCodecs
internal import TerminalKitInput

/// What a gateway viewer's terminal may do when `policy.gatewayApprovals` is false (ADR-0170): watch, scroll, and unfold the command
/// an approval asks about, never answer or dismiss the approval itself.
extension ScreenController {
    /// Applies `event` from a viewer's terminal.
    mutating func handleMirror(_ event: InputEvent, pageRows: Int, columns: Int? = nil) -> [Effect] {
        guard var pending = state.pendingApproval, !options.mirrorApprovalsAllowed else {
            return handle(event, pageRows: pageRows, columns: columns)
        }
        if case .key(let key) = event {
            switch key.keyCode {
                case Key.pageUp.rawValue:
                    scroll(by: Swift.max(1, pageRows))
                    return []
                case Key.pageDown.rawValue:
                    scroll(by: -Swift.max(1, pageRows))
                    return []
                case 0x0F:
                    toggleApprovalDetail()
                    return []
                default: break
            }
        }
        if !pending.mirrorRefused {
            pending.mirrorRefused = true
            state.pendingApproval = pending
            state.transcript.addNotice(
                "Approvals must be answered at the computer (policy.gatewayApprovals).",
                isError: false
            )
        }
        return []
    }
}
