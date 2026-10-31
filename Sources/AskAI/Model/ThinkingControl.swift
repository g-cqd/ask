/// The selected request control, after the provider's capabilities have been considered. Nil on a request preserves
/// provider defaults. This is deliberately separate from the user's level: off can mean disabled or between-tools,
/// and an older model may need a concrete budget instead of a named effort.
public enum ThinkingControl: Sendable, Equatable {
    case disabled
    case betweenTools
    case effort(ThinkingLevel)
    case budget(tokens: Int, effort: ThinkingLevel?)
    /// The model's own adaptive thinking at its default effort: what a model that always thinks does with no control, sent so that the
    /// thinking's summary can be asked for (``providerDefault(descriptor:)``).
    case adaptive
}
