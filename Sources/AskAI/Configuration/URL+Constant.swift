internal import Foundation

extension URL {
    /// A URL ask writes itself, an address of a provider's or a path of ours under one: it always parses, and one that did not would
    /// be a mistake in ask, stopped at once with what it was, rather than a force unwrap (the swift-ci discipline).
    static func constant(_ text: String) -> URL {
        guard let url = URL(string: text) else { preconditionFailure("ask's own address does not parse: \(text)") }
        return url
    }
}
