/// What Cloud Code says about the signed-in account: the project every inference request must carry, and the tiers it reports.
public struct AgyAccount: Sendable, Equatable {
    public let projectID: String
    public let currentTierID: String?
    public let paidTierID: String?
}
