internal import Foundation

/// A pasted API key, checked before it is stored or sent: the check that keeps a key from splitting a header or filling a file.
public enum APIKey {
    /// The most bytes a key may have.
    public static let lengthLimit = 4096

    /// `raw` without the whitespace around it, or nil when what is left is empty, too long, or holds a space, a control character or
    /// anything outside visible ASCII.
    public static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= lengthLimit,
            trimmed.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E })
        else { return nil }
        return trimmed
    }
}
