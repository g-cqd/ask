/// Which copy notices are worth a person's attention: only the ones that say something went wrong. A copy that was sent or done is just a copy.
enum ClipboardNotice {
    static func needsAttention(_ notice: String) -> Bool {
        guard !notice.isEmpty else { return false }
        return ["failed", "too large", "unavailable", "Nothing selected"].contains { notice.contains($0) }
    }
}
