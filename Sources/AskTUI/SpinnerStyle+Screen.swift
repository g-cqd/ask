public import AskCore

/// Built-in spinner frame sequences for status indicators and active progress.
extension SpinnerStyle {
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
            // `dot` and `star` never reach the screen (the run draws its default instead), and `random` is resolved first.
            case .random, .dot, .star:
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
