internal import Foundation
internal import TerminalKitInput

/// The `@` picker (roadmap 0048, ADR-0069): the project's files, chosen into the draft as `@path`. Nothing is attached or read: the
/// draft gets the text, and the model reads the file with its own tools, under the sandbox.
extension ScreenController {
    /// How old a listing may be before the next `@` word asks for a fresh one.
    static let filesMaxAge = Duration.seconds(10)

    /// The `@` word the cursor is in, if the draft has an `@` at all.
    func fileTrigger() -> CompletionTrigger? {
        // Most drafts never contain an @, so one libc scan of the bytes decides before anything walks the draft to the cursor.
        // A native string is contiguous; the generic byte loop it replaces cost 8 µs a key on a 6 KB draft.
        guard Self.containsAt(state.editor.text) else { return nil }
        return CompletionTrigger.at(cursor: state.editor.cursor, in: state.editor.text, sigils: ["@"])
    }

    /// Whether `text` holds an `@` anywhere.
    private static func containsAt(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return false }
            return memchr(base, Int32(UInt8(ascii: "@")), bytes.count) != nil
        }
    }

    /// Opens, narrows or closes the file picker for `trigger`, asking for a listing when there is none or it has aged. It stays closed
    /// for a path typed in full (nothing is left to insert), for no match, and for a word the user closed it on.
    /// - Returns: asking for the listing, when it is needed and not already asked for.
    mutating func refreshFilePicker(
        _ trigger: CompletionTrigger, screenRows: Int, at now: ContinuousClock.Instant
    ) -> [Effect] {
        guard state.pickerDismissedAt != trigger.range.lowerBound else {
            state.picker = nil
            return []
        }
        var effects: [Effect] = []
        let aged = state.filesLoadedAt.map { now - $0 > Self.filesMaxAge } ?? true
        if aged, !state.filesLoading {
            state.filesLoading = true
            effects = [.indexFiles]
        }
        let capacity = CompletionPicker.capacity(screenRows: screenRows)
        guard let files = state.files else {
            install(
                CompletionPicker(
                    kind: .files, trigger: trigger, matches: [], capacity: capacity, caption: "looking for files…"))
            return effects
        }
        // A range typed after the path, `@file:12-30`, is kept on whatever path is chosen.
        let colon = trigger.query.firstIndex(of: ":")
        let query = colon.map { String(trigger.query[..<$0]) } ?? trigger.query
        let range = colon.map { String(trigger.query[$0...]) } ?? ""
        let ranked = PickerRanking.rank(files: files, query: query)
        guard !ranked.indices.isEmpty, !ranked.indices.contains(where: { files.paths[$0] == query }) else {
            state.picker = nil
            return effects
        }
        let caption = [
            files.hidden > 0 ? "\(files.hidden) hidden by the sandbox" : nil,
            files.truncated ? "listing cut at its limit" : nil,
            ranked.capped ? "first \(PickerRanking.fileLimit) matches" : nil
        ]
        .compactMap { $0 }.joined(separator: " · ")
        install(
            CompletionPicker(
                kind: .files, trigger: trigger,
                matches: ranked.indices.map {
                    PickerRow(label: files.paths[$0], insertion: Self.reference(to: files.paths[$0]) + range)
                },
                capacity: capacity, caption: caption))
        return effects
    }

    /// How the draft refers to `path`: `@path`, or `@"path"` when the name has whitespace in it, which would otherwise end the word.
    static func reference(to path: String) -> String {
        path.contains(where: \.isWhitespace) ? "@\"" + path + "\"" : "@" + path
    }

    /// Takes the listing the conversation made, and refreshes the picker the user may be waiting on.
    mutating func receive(files: ProjectFiles) -> [Effect] {
        state.files = files
        state.filesLoadedAt = .now
        state.filesLoading = false
        guard pickerScreenRows >= Self.pickerMinimumRows, let trigger = fileTrigger() else { return [] }
        return refreshFilePicker(trigger, screenRows: pickerScreenRows, at: .now)
    }
}
