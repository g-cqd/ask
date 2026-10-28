internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import TerminalKitInput

/// Follows the terminal's own colours (roadmap 0108). It asks for the foreground and the background, reads the answers out of the input, and
/// asks again when macOS changes appearance, because Apple Terminal's default profiles change their colours with the system.
struct TerminalColours {
    /// The OSC 10 and OSC 11 queries. Unlike the kit's `OSCPalette.query`, no device-attributes request closes them: the session's keyboard
    /// probe owns that reply, and a terminal that ignores the queries simply never answers, which leaves the first guess in place.
    static let query = Array("\u{1b}]10;?\u{1b}\\\u{1b}]11;?\u{1b}\\".utf8)
    /// The distributed notification macOS posts when the appearance changes between light and dark.
    static let appearanceChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
    /// The waits before each new question after a change, one after the other: a terminal may repaint its profile a little after the
    /// notification.
    static let askAgain: [Duration] = [.milliseconds(150), .seconds(1)]

    private let connection: any TerminalConnection
    private var foreground: SIMD3<Double>?

    /// What the screen does with an event the colours took.
    enum Taken: Equatable {
        /// The terminal's page is now known: mix the tints from it.
        case page(ScreenTheme.Page)
        /// Nothing to draw: a question was sent, or half an answer came.
        case consumed
    }

    /// Colours that follow the terminal over `connection`, or nil when the screen does not follow them (see ``follows(_:)``).
    init?(following options: ScreenOptions, connection: any TerminalConnection) {
        guard Self.follows(options) else { return nil }
        self.connection = connection
    }

    /// Asks the terminal for its colours off the screen's loop, which never waits on a write; the answers arrive as input.
    func ask() {
        let connection = connection
        Task.detached { try? connection.write(Self.query) }
    }

    /// Takes the events that are the colours' own: a reason to ask again, and the terminal's answers, which are never keys. Nil for the rest.
    mutating func take(_ event: ScreenEvent) -> Taken? {
        switch event {
            case .askColours:
                ask()
                return .consumed
            case .input(.unknown(let bytes)) where Self.isAnswer(bytes):
                return read(bytes).map(Taken.page) ?? .consumed
            default:
                return nil
        }
    }

    /// Whether `bytes` answers a colour query. An answer is never a key, whether or not it completes a page.
    static func isAnswer(_ bytes: [UInt8]) -> Bool {
        switch OSCPalette.parse(bytes) {
            case .foreground, .background: true
            default: false
        }
    }

    /// The page an answer completes: the background, with the foreground that came before it. Nil for the foreground alone or anything else.
    mutating func read(_ bytes: [UInt8]) -> ScreenTheme.Page? {
        switch OSCPalette.parse(bytes) {
            case .foreground(let color):
                foreground = Self.channels(color)
                return nil
            case .background(let color):
                return ScreenTheme.Page(background: Self.channels(color), foreground: foreground)
            default:
                return nil
        }
    }

    /// Whether the screen follows the terminal's colours: with `ui.appearance` on auto, tinted or not, because secondary text is mixed from
    /// them too.
    static func follows(_ options: ScreenOptions) -> Bool { options.appearance == .auto }

    /// Calls `changed` whenever macOS switches between light and dark. Remove the observer with ``stopWatching(_:)``.
    static func watchAppearance(_ changed: @escaping @Sendable () -> Void) -> any NSObjectProtocol {
        DistributedNotificationCenter.default()
            .addObserver(forName: appearanceChanged, object: nil, queue: nil) { _ in changed() }
    }

    /// Calls `ask` after each wait of ``askAgain`` whenever `appearances` reports a change, until the task is cancelled.
    static func askAgain(after appearances: AsyncStream<Void>, _ ask: @escaping @Sendable () -> Void) -> Task<
        Void, Never
    > {
        Task {
            for await _ in appearances {
                for delay in askAgain {
                    try? await Task.sleep(for: delay)
                    ask()
                }
            }
        }
    }

    static func stopWatching(_ observer: any NSObjectProtocol) {
        DistributedNotificationCenter.default().removeObserver(observer)
    }

    private static func channels(_ color: ColorRGB) -> SIMD3<Double> {
        SIMD3(Double(color.r), Double(color.g), Double(color.b))
    }
}
