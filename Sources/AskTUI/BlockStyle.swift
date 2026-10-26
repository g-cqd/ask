/// How the transcript's blocks are laid out (roadmap 0074): with one row of padding around each and a tint by kind, or as plain text.
public struct BlockStyle: Sendable, Equatable {
    /// Whether each block has a row of padding above and below it, an inset of one column, and a blank row before it when it and the block
    /// above are both tool calls or the user's messages.
    public var padded: Bool
    public var theme: ScreenTheme

    public init(padded: Bool = true, theme: ScreenTheme = ScreenTheme()) {
        self.padded = padded
        self.theme = theme
    }

    /// The older look: text with no padding, no inset and no tint.
    public static let plain = BlockStyle(padded: false, theme: ScreenTheme(tinted: false))

    /// How many columns a block's text is inset from each edge.
    var inset: Int { padded ? 1 : 0 }
}
