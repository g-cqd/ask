internal import AemiJSON
internal import AskAI

/// Members removed and added in the file's own style (roadmap 0170): its indentation, key quoting, separator and trailing commas.
extension ConfigSourceEdit {
    /// Removes `gone` from `node` and adds `added` after what is left.
    mutating func changeMembers(
        of node: JSON,
        members: [Member],
        removing gone: [Member],
        adding added: OrderedDictionary<String, JSONValue>
    ) {
        let kept = members.filter { member in !gone.contains { $0.keyRange == member.keyRange } }
        let trailing = members.last.map { comma(after: $0) != nil } ?? false
        for member in gone { remove(member) }
        // The last member gone in a file without trailing commas: the one now last loses its comma, unless members follow it.
        if let last = members.last, gone.contains(where: { $0.keyRange == last.keyRange }), !trailing, added.isEmpty,
            let anchor = kept.last, let comma = comma(after: anchor)
        {
            edits.append((comma ..< comma + 1, []))
        }
        guard !added.isEmpty else { return }
        insert(added, into: node, after: kept.last, trailing: trailing, like: members.first)
    }

    /// The offset of the comma right after `member`'s value, past white space and comments; nil when none follows.
    func comma(after member: Member) -> Int? {
        let next = text.significant(from: member.valueRange.upperBound)
        return next < text.bytes.count && text.bytes[next] == UInt8(ascii: ",") ? next : nil
    }

    /// Removes `member` with its comma; a member on lines of its own goes with those lines and the comment lines right above it.
    mutating func remove(_ member: Member) {
        var end = comma(after: member).map { $0 + 1 } ?? member.valueRange.upperBound
        var start = member.keyRange.lowerBound
        if text.startsLine(start), let lineEnd = text.restOfLineEnd(from: end) {
            start = text.commentLinesAbove(text.lineStart(start))
            end = lineEnd
        } else {
            while end < text.bytes.count, text.bytes[end] == UInt8(ascii: " ") { end += 1 }
        }
        edits.append((start ..< end, []))
    }

    /// What `member`'s file writes between a key and its value: `: `, `:` or ` : `.
    func separatorText(_ member: Member?) -> String {
        guard let member else { return separator }
        return String(decoding: text.bytes[member.keyRange.upperBound ..< member.valueRange.lowerBound], as: UTF8.self)
    }

    /// Adds `added` to `node`: after `anchor`, the last member kept, on lines of their own when it is on its own, or in place of
    /// `node`'s text when it has none left.
    mutating func insert(
        _ added: OrderedDictionary<String, JSONValue>,
        into node: JSON,
        after anchor: Member?,
        trailing: Bool,
        like first: Member?
    ) {
        let separator = separatorText(first)
        guard let anchor else {
            insertIntoEmpty(added, node: node, separator: separator, like: first)
            return
        }
        let inline = !text.startsLine(anchor.keyRange.lowerBound)
        let indent = memberIndent(anchor)
        let range = node.sourceRange ?? anchor.valueRange
        let spaced = text.bytes[range].starts(with: [UInt8(ascii: "{"), UInt8(ascii: " ")])
        let lead = inline ? (spaced ? " " : "") : "\n" + indent
        let entries = added.map { key, value in
            lead
                + String(
                    decoding: keyText(key, like: first) + Array(separator.utf8) + valueText(value, indent: indent),
                    as: UTF8.self
                )
        }
        let body = entries.joined(separator: ",") + (trailing ? "," : "")
        if let comma = comma(after: anchor) {
            edits.append((comma + 1 ..< comma + 1, Array(body.utf8)))
        } else {
            let end = anchor.valueRange.upperBound
            edits.append((end ..< end, Array(("," + body).utf8)))
        }
    }

    /// `node`'s text replaced by an object of `added`, indented one level past the line it opens on.
    private mutating func insertIntoEmpty(
        _ added: OrderedDictionary<String, JSONValue>,
        node: JSON,
        separator: String,
        like first: Member?
    ) {
        guard let range = node.sourceRange else { return }
        let parent = text.indentation(atLineOf: range.lowerBound)
        let child = parent + indentUnit
        let entries = added.map { key, value in
            String(
                decoding: keyText(key, like: first) + Array(separator.utf8) + valueText(value, indent: child),
                as: UTF8.self
            )
        }
        let object =
            multiline
            ? "{\n" + entries.map { child + $0 }.joined(separator: ",\n") + "\n" + parent + "}"
            : "{" + entries.joined(separator: ",") + "}"
        edits.append((range, Array(object.utf8)))
    }
}
