/// What a session line that does not decode says of itself (ADR-0144): its record type and, for an entry, its identity and its
/// payload's kind. Enough to tell a newer ask's record or entry, which is kept, from damage, which is not.
struct SessionLogProbe: Decodable {
    struct Payload: Decodable {
        let kind: String?
    }

    let type: String
    let id: String?
    let parent: String?
    let payload: Payload?
}
