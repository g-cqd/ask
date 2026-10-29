internal import TerminalKitCodecs
internal import TerminalKitIO
internal import TerminalKitInput

/// Follows the terminal's own colours (roadmap 0108): the screen's side of TerminalKit's `PageFollower`, which asks, recognises the answers and
/// reads the page. This type maps them to the screen's events and decides whether to follow at all.
struct TerminalColours {
    private let connection: any TerminalConnection
    private var follower = PageFollower()

    /// What the screen does with an event the colours took.
    enum Taken: Equatable {
        /// The terminal's page is now known: mix the tints from it.
        case page(TerminalPage)
        /// Nothing to draw: a question was sent, or half an answer came.
        case consumed
    }

    /// Colours that follow the terminal over `connection`, or nil when the screen does not follow them (see ``follows(_:)``).
    init?(following options: ScreenOptions, connection: any TerminalConnection) {
        guard Self.follows(options) else { return nil }
        self.connection = connection
    }

    /// Asks the terminal for its colours off the screen's loop, which never waits on a write; the answers arrive as input.
    func ask() { PageFollower.ask(over: connection) }

    /// Takes the events that are the colours' own: a reason to ask again, and the terminal's answers, which are never keys. Nil for the rest.
    mutating func take(_ event: ScreenEvent) -> Taken? {
        switch event {
            case .askColours:
                ask()
                return .consumed
            case .input(.unknown(let bytes)) where PageFollower.isAnswer(bytes):
                return follower.read(bytes).map(Taken.page) ?? .consumed
            default:
                return nil
        }
    }

    /// Whether the screen follows the terminal's colours: with `ui.appearance` on auto, tinted or not, because secondary text is mixed from
    /// them too.
    static func follows(_ options: ScreenOptions) -> Bool { options.appearance == .auto }
}
