/// Why a call's changes were refused (ADR-0141): which change, which operation, and why. Nothing of the call was made.
public struct ListPlanError: Error, Equatable, Sendable {
    /// 1-based; 0 for the call as a whole (a read, or too many changes).
    public let index: Int
    public let operation: String
    public let reason: String

    public init(index: Int, operation: String, reason: String) {
        self.index = index
        self.operation = operation
        self.reason = reason
    }

    public var words: String {
        index == 0
            ? "Refused, nothing changed: \(reason)"
            : "Refused, nothing changed: change \(index) (\(operation)): \(reason)"
    }
}
