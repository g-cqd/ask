/// A whole number that a server may have sent as anything else. A number that is not a whole one, a string, a list or a
/// null is nil here, which costs the one field and not the response around it.
struct LenientInt: Decodable, Sendable {
    let value: Int?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Int.self)
    }
}
