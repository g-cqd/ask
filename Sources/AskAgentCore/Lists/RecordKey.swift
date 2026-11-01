/// A coding key of any name: for records whose layout was set before they had a `kind` (the ideas' first records), and for tool input
/// whose every field is seen so the ones not asked for are refused (ADR-0141).
public struct RecordKey: CodingKey, Sendable {
    public let stringValue: String
    public var intValue: Int? { nil }

    public init(_ name: String) { stringValue = name }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}
