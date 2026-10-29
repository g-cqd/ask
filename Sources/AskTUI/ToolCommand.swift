internal import Foundation
internal import TerminalKitText

/// What the screen is told of a tool whose input is a command (roadmap 0080): the command itself is the tool's full input and heads its
/// block, after the limits it was given.
public struct ToolCommand: Sendable, Equatable {
    /// How long the command may run, if the call said.
    public var timeout: Duration?
    /// How long ask waits before leaving it running in the background, if the call said.
    public var yield: Duration?
    /// The tool's own timeout, which `ui.timeout` `auto` leaves unwritten; nil when the tool has none or it is not known.
    public var defaultTimeout: Duration?

    public init(timeout: Duration? = nil, yield: Duration? = nil, defaultTimeout: Duration? = nil) {
        self.timeout = timeout
        self.yield = yield
        self.defaultTimeout = defaultTimeout
    }

    /// The widest a timeout's label is drawn (`ui.timeoutLabel`), in cells.
    static let labelCells = 8

    /// The limits as the header writes them.
    /// - Parameters:
    ///   - localized: the locale's units (`2 min`) rather than a clock (`2:00`).
    ///   - display: which limits are written (`ui.timeout`).
    ///   - label: the word in front of the timeout (`ui.timeoutLabel`), cut to ``labelCells`` cells.
    ///   - locale: the locale of the units.
    /// - Returns: `timeout 2 min · yield 5 sec`, or `timeout 2:00 · yield 0:05`; empty when nothing is to be written.
    func parameters(
        localized: Bool, display: TimeoutDisplay = .always, label: String = "timeout", locale: Locale = .current
    ) -> String {
        func text(_ duration: Duration) -> String {
            let seconds = duration.components.seconds
            return localized
                ? DurationText.localized(seconds, locale: locale) : DurationText.clock(seconds, minutes: true)
        }
        let shownTimeout: Duration? =
            switch display {
                case .never: nil
                case .always: timeout
                case .auto: timeout == defaultTimeout ? nil : timeout
            }
        let shownYield = display == .never ? nil : yield
        return [shownTimeout.map { Self.clipped(label) + " " + text($0) }, shownYield.map { "yield " + text($0) }]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// `label` cut to the characters that fit in ``labelCells`` cells.
    private static func clipped(_ label: String) -> String {
        var cells = 0
        var kept = ""
        for character in label {
            cells += UnicodeWidth.displayWidth(of: String(character))
            guard cells <= labelCells else { break }
            kept.append(character)
        }
        return kept
    }
}
