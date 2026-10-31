/// A model with every account of one subscription that serves it: one row of `/model`, however many accounts (roadmap 0092).
public struct ModelOfferGroup: Sendable, Equatable {
    /// The server's model id.
    public let model: String
    /// The subscription its accounts are; nil for a provider reached with a key, which is never grouped.
    public let kind: ConnectionKind?
    /// The accounts that serve it, in the order they were listed.
    public private(set) var accounts: [String]

    /// The offers as groups, each in the place of its first offer: a model is grouped across the accounts of one subscription only.
    public static func grouped(_ offers: [ModelOffer]) -> [ModelOfferGroup] {
        var groups: [ModelOfferGroup] = []
        var index: [String: Int] = [:]
        for offer in offers {
            guard let kind = offer.kind else {
                groups.append(ModelOfferGroup(model: offer.model, kind: nil, accounts: [offer.account]))
                continue
            }
            let key = "\(kind.rawValue)\u{0}\(offer.model)"
            if let at = index[key] {
                if !groups[at].accounts.contains(offer.account) { groups[at].accounts.append(offer.account) }
            } else {
                index[key] = groups.count
                groups.append(ModelOfferGroup(model: offer.model, kind: kind, accounts: [offer.account]))
            }
        }
        return groups
    }
}
