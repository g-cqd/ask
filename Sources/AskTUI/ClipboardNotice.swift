/// Which copy and link notices are worth a person's attention: only the ones that say something did not happen as asked. A copy that
/// was sent or done is just a copy; a link that opened opened.
enum ClipboardNotice {
    static func needsAttention(_ notice: String) -> Bool {
        guard !notice.isEmpty else { return false }
        return [
            "failed", "too large", "unavailable", "Nothing selected", "Not opened", "not opened", "Nothing opened",
            "Not run"
        ]
        .contains { notice.contains($0) }
    }
}
