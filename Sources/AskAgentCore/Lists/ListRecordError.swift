/// A record a later ask wrote (ADR-0141): its kind is not one this build knows. The list is then read-only, never rewritten without it.
public struct ListRecordError: Error, Equatable, Sendable {
    public let kind: String
}
