internal import TerminalKitStyle

/// The tints of the screen (roadmap 0074): a terminal has no alpha, so "a little darker than the page" is a fixed colour chosen for a dark or a
/// light terminal. They are guesses until the terminal's own background is read (the kit's `OSCPalette`; see the TerminalKit handover).
public struct ScreenTheme: Sendable, Equatable {
    /// Whether anything is tinted.
    public var tinted: Bool
    var input: Color
    var pending: Color
    var success: Color
    var failure: Color
    var user: Color

    public init(tinted: Bool = true, light: Bool = false) {
        self.tinted = tinted
        // @dl:accept -- two colour tables, light and dark: their rows repeat their shape by being rows
        if light {
            input = .rgb(r: 236, g: 237, b: 241)
            user = .rgb(r: 232, g: 234, b: 242)
            pending = .rgb(r: 233, g: 233, b: 241)
            success = .rgb(r: 230, g: 241, b: 232)
            failure = .rgb(r: 246, g: 230, b: 230)
        } else {
            input = .rgb(r: 38, g: 40, b: 48)
            user = .rgb(r: 44, g: 47, b: 60)
            pending = .rgb(r: 36, g: 38, b: 50)
            success = .rgb(r: 34, g: 46, b: 38)
            failure = .rgb(r: 58, g: 38, b: 40)
        }
    }

    /// The background of a block of this kind: the user's messages and the tool calls are tinted (a tool by how it ended), nothing else is.
    func tint(for item: Transcript.Item) -> Color {
        guard tinted else { return .default }
        switch item {
            case .user: return user
            case .tool(_, _, let status, _):
                switch status {
                    case .running: return pending
                    case .succeeded: return success
                    case .failed: return failure
                }
            default: return .default
        }
    }

    /// The input's background, or the terminal's own when nothing is tinted.
    var inputBackground: Color { tinted ? input : .default }
}
