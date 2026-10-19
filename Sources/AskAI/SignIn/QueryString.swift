internal import Foundation

/// A URL query read strictly: the one reader the callback listener and a pasted address share, so both refuse what the
/// other would.
enum QueryString {
    struct Item: Equatable, Sendable {
        let name: String
        let value: String
    }

    /// The items of `query`, or nil when a component has a bad percent escape.
    static func items(in query: String) -> [Item]? {
        var items: [Item] = []
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = decode(halves[0]), let value = decode(halves.count == 2 ? halves[1] : "") else {
                return nil
            }
            items.append(Item(name: name, value: value))
        }
        return items
    }

    /// The value of `name` in `items`, when it is given exactly once.
    static func value(of name: String, in items: [Item]) -> String? {
        let matches = items.filter { $0.name == name }
        return matches.count == 1 ? matches[0].value : nil
    }

    /// A query component as a form encodes it: `+` is a space, and a bad percent escape is an error.
    private static func decode(_ component: Substring) -> String? {
        component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
