/// Intact registrations and diagnostics for unreadable ones; a damaged account must not hide every other account.
public struct ConnectionListing: Sendable {
    public let records: [ConnectionRecord]
    public let notices: [String]
}
