internal import Foundation

/// What the screen is told of a tool whose input is a command (roadmap 0080): the command itself is the tool's full input and heads its
/// block, after the limits it was given.
public struct ToolCommand: Sendable, Equatable {
    /// How long the command may run, if the call said.
    public var timeout: Duration?
    /// How long ask waits before leaving it running in the background, if the call said.
    public var yield: Duration?

    public init(timeout: Duration? = nil, yield: Duration? = nil) {
        self.timeout = timeout
        self.yield = yield
    }

    /// `timeout 2 min · yield 5 sec`, or with `localized` off `timeout 2:00 · yield 0:05`; empty when the call set neither.
    func parameters(localized: Bool, locale: Locale = .current) -> String {
        func text(_ duration: Duration) -> String {
            let seconds = duration.components.seconds
            return localized
                ? DurationText.localized(seconds, locale: locale) : DurationText.clock(seconds, minutes: true)
        }
        return [timeout.map { "timeout " + text($0) }, yield.map { "yield " + text($0) }].compactMap(\.self)
            .joined(separator: " · ")
    }
}
