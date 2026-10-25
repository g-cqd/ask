extension DefinitionFile {
    /// The value of the first of `keys` the head has, comparing keys by meaning (`canonicalKey`).
    public func value(_ keys: String...) -> DefinitionValue? {
        for key in keys {
            let wanted = key.canonicalKey
            if let entry = entries.first(where: { $0.canonical == wanted }) { return entry.value }
        }
        return nil
    }

    /// The scalar text of the first of `keys` that has one, trimmed.
    public func text(_ keys: String...) -> String? {
        for key in keys {
            let wanted = key.canonicalKey
            if let text = entries.first(where: { $0.canonical == wanted })?.value.scalar?.trimmingWhitespace(),
                !text.isEmpty
            {
                return text
            }
        }
        return nil
    }

    /// The comment hint named `key`, if any (`# fallback_models: a, b`).
    public func hint(_ key: String) -> DefinitionValue? {
        let wanted = key.canonicalKey
        return hints.first { $0.canonical == wanted }?.value
    }

    /// Records a comment as a hint when it reads as `key: value` or `key = value`.
    static func hint(fromComment comment: String) -> DefinitionEntry? {
        let text = comment.trimmingWhitespace()
        guard let split = text.firstIndex(where: { $0 == ":" || $0 == "=" }) else { return nil }
        let key = String(text[..<split]).trimmingWhitespace()
        let value = String(text[text.index(after: split)...]).trimmingWhitespace()
        guard !key.isEmpty, key.count <= 40, !value.isEmpty,
            key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return nil }
        let parsed = value.first == "[" ? FlowParser.parse(value) : DefinitionValue.text(value)
        return DefinitionEntry(key: key, value: parsed)
    }
}
