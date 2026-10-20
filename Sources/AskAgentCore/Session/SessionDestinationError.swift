/// A written safety reason for refusing to send recorded history through an implicitly changed account.
public enum SessionDestinationError: Error, Sendable, Equatable, CustomStringConvertible {
    case unbound
    case changed

    public var description: String {
        switch self {
            case .unbound:
                "this session has no recorded destination; pass --provider explicitly before sending its history"
            case .changed:
                "this session belongs to another connection or authorization; pass --provider explicitly to authorize switching"
        }
    }
}
