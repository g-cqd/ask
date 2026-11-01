extension String {
    /// Nothing but white space, or nothing at all: a title or an idea that says nothing.
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
