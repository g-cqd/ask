/// One thing a script said, in the order it said it: text (from `text()` or its `return`), or a line of its console.
package struct CodemodeItem: Sendable, Equatable, Codable {
    package let text: String
    /// Whether it came from `console.*`: those follow the other output in the result, in a block of their own.
    package let console: Bool

    package init(text: String, console: Bool = false) {
        self.text = text
        self.console = console
    }
}
