internal import AemiJSONRPC
internal import AskCodemode
internal import Synchronization

/// What a script has said so far, as its keeper holds it (ADR-0156). Each thing a script says crosses to its keeper as it is
/// said (``CodemodeWire/said``), so a script stopped at its deadline or at its memory keeps what it had said.
final class CodemodeSaid: Sendable {
    /// The most kept, in UTF-8 bytes: more than any text within ``CodemodeVM/maximumCharacters`` comes to. A script's process
    /// holds itself to what a script may say; this is for one that does not.
    static let maximumBytes = CodemodeVM.maximumCharacters * 4

    private let kept = Mutex((items: [CodemodeItem](), bytes: 0))

    /// What the script has said, in the order it said it.
    var items: [CodemodeItem] { kept.withLock { $0.items } }

    /// Keeps what `notification` says the script said. False when that is past what a script may say.
    func take(_ notification: JSONRPCNotification) -> Bool {
        guard notification.method == CodemodeWire.said, let item = CodemodeWire.item(from: notification.params) else {
            return true
        }
        return kept.withLock { kept in
            let bytes = kept.bytes + item.text.utf8.count
            guard kept.items.count < CodemodeVM.maximumItems, bytes <= Self.maximumBytes else { return false }
            kept.bytes = bytes
            kept.items.append(item)
            return true
        }
    }
}
