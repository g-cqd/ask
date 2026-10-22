/// A model's reported ways of controlling thinking. These describe capability metadata, not a promise that every
/// compatible spelling is listed or that a request will be accepted.
public enum ThinkingMode: String, Codable, Sendable, CaseIterable {
    case disabled
    case enabled
    case adaptive
    case betweenTools = "between_tools"
}
