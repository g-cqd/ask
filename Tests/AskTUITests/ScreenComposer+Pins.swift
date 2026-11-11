@testable import AskTUI

extension ScreenComposer.Line {
    /// The row's links as the characterisation digests were pinned on them: before a link held the place written after its path
    /// (roadmap 0216). A link without one reads as it did, so the digests move only where a place is found.
    var pins: String {
        "["
            + links.map { String(reflecting: $0).replacing(", line: nil, column: nil", with: "") }
            .joined(separator: ", ") + "]"
    }
}
