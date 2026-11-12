internal import AemiJSON
internal import AskAI

/// A `/config` change made in the file's own text (roadmap 0170; the owner, 2026-10-31: keep the file's comments). The file's tree and
/// the tree to save are compared; only what differs is written: a changed value's bytes, a removed member with its separator and
/// its own comment lines, a new one in the file's style, an old name renamed where it stands. The result must parse as the tree to
/// save, or nothing is offered and the editor writes the file anew, as before.
struct ConfigSourceEdit {
    /// One member of an object as written.
    struct Member {
        let key: String
        let keyRange: Range<Int>
        let value: JSON
        var valueRange: Range<Int> { value.sourceRange ?? keyRange }
    }

    let text: ConfigSourceText
    let indentUnit: String
    let separator: String
    /// Whether the file spans lines, so a new object is written on lines of its own.
    let multiline: Bool
    var edits: [(range: Range<Int>, bytes: [UInt8])] = []

    /// `source` changed so that it reads as `target`, or nil when that cannot be done in place.
    static func edited(_ source: [UInt8], to target: JSONValue, format: ConfigEditorFormat) -> [UInt8]? {
        var options = JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
        options.recordsContainerSpans = true
        guard let document = try? AemiJSON.parse(source, options: options), document.root.isObject,
            case .object(let wanted) = target
        else { return nil }
        var edit = ConfigSourceEdit(
            text: ConfigSourceText(bytes: source),
            indentUnit: format.indent,
            separator: format.foundationSeparator ? " : " : ": ",
            multiline: format.pretty
        )
        edit.object(document.root, wanted: wanted)
        var bytes = source
        for change in edit.edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(change.range, with: change.bytes)
        }
        guard let reread = try? AemiJSON.parse(bytes, options: .json5), JSONValue(reread.root) == target else {
            return nil
        }
        return bytes
    }

    /// The members of `node`, an object, in document order.
    static func members(of node: JSON) -> [Member] {
        var members: [Member] = []
        node.forEachMemberWithKeyRange { key, range, value in
            members.append(Member(key: key, keyRange: range, value: value))
        }
        return members
    }

    /// Brings `node`, an object as written, to `wanted`.
    mutating func object(_ node: JSON, wanted: OrderedDictionary<String, JSONValue>) {
        let members = Self.members(of: node)
        if wanted.isEmpty, !members.isEmpty, let range = node.sourceRange {
            edits.append((range, Array("{}".utf8)))
            return
        }
        var removed: [Member] = []
        for member in members {
            guard let new = wanted[member.key] else {
                removed.append(member)
                continue
            }
            guard JSONValue(member.value) != new else { continue }
            if case .object(let inner) = new, member.value.isObject {
                object(member.value, wanted: inner)
            } else {
                edits.append((member.valueRange, valueText(new, indent: memberIndent(member))))
            }
        }
        var added = wanted.filter { key, _ in !members.contains { $0.key == key } }
        // An old name whose value is unchanged is renamed where it stands, keeping its comments and its value as written.
        var renamed: [Member] = []
        for member in removed {
            guard let index = added.elements.firstIndex(where: { $0.value == JSONValue(member.value) }) else {
                continue
            }
            edits.append((member.keyRange, keyText(added.elements[index].key, like: member)))
            added.removeValue(forKey: added.elements[index].key)
            renamed.append(member)
        }
        let gone = removed.filter { member in !renamed.contains { $0.keyRange == member.keyRange } }
        changeMembers(of: node, members: members, removing: gone, adding: added)
    }

    /// The indentation of the line `member`'s key starts.
    func memberIndent(_ member: Member) -> String { text.indentation(atLineOf: member.keyRange.lowerBound) }

    /// `value` as written in this file, its lines after the first indented to follow `indent`.
    func valueText(_ value: JSONValue, indent: String) -> [UInt8] {
        let pretty: Bool = if case .object(let members) = value { !members.isEmpty } else { false }
        let options = JSONEncodingOptions(
            prettyPrinted: pretty,
            prettyKeySeparator: separator == " : " ? .foundation : .javaScript,
            indent: indentUnit == "\t" ? .string("\t") : .spaces(indentUnit.count)
        )
        guard let bytes = try? value.encodedBytes(options: options) else { return Array("null".utf8) }
        return Array(String(decoding: bytes, as: UTF8.self).replacing("\n", with: "\n" + indent).utf8)
    }

    /// `key` quoted as `like`'s key is, or bare when that is bare and `key` may be.
    func keyText(_ key: String, like member: Member?) -> [UInt8] {
        let quote = member.flatMap { text.bytes[$0.keyRange.lowerBound] == UInt8(ascii: "'") ? "'" : nil }
        let bare = member.map { text.bytes[$0.keyRange.lowerBound] != UInt8(ascii: "\"") && quote == nil } ?? false
        let identifier =
            key.first.map { $0.isLetter || $0 == "_" || $0 == "$" } == true
            && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        if bare, identifier { return Array(key.utf8) }
        let encoded = (try? JSONValue.string(key).encodedBytes()) ?? Array("\"\(key)\"".utf8)
        guard quote == "'", !key.contains("'") else { return encoded }
        return Array(("'" + String(decoding: encoded.dropFirst().dropLast(), as: UTF8.self) + "'").utf8)
    }
}
