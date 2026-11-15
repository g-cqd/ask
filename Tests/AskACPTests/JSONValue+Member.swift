import AemiJSON

extension JSONValue {
    /// The member `key` of an object; nil for anything else, or an object without it.
    subscript(_ key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    /// The items of an array; nil for anything else.
    var items: [JSONValue]? {
        guard case .array(let items) = self else { return nil }
        return items
    }
}
