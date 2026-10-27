internal import Foundation

/// Built-in spinner frame sequences for status indicators and active progress.
public enum SpinnerStyle: String, Sendable, CaseIterable {
    case braille
    case braillefull
    case braillequarter
    case snake
    case line
    case dot
    case star
    case random

    /// Concrete non-random styles.
    public static let allConcrete: [SpinnerStyle] = [
        .braille, .braillefull, .braillequarter, .snake, .line, .dot, .star
    ]

    /// The frames for this spinner style.
    public var frames: [String] {
        switch self {
            case .braille:
                return ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            case .braillefull:
                return ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
            case .braillequarter:
                return ["⠁", "⠂", "⠄", "⠂"]
            case .snake:
                return ["⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂", "⠁"]
            case .line:
                return ["|", "/", "-", "\\"]
            case .dot:
                return ["·", "•", "·"]
            case .star:
                return ["✶", "✸", "✹", "✺", "✹", "✷"]
            case .random:
                return Self.line.frames
        }
    }

    /// Chooses one concrete style randomly.
    public static func randomConcrete() -> SpinnerStyle {
        allConcrete.randomElement() ?? .line
    }

    /// Resolves this style into a concrete frame provider.
    public func resolved() -> SpinnerStyle {
        self == .random ? Self.randomConcrete() : self
    }
}
