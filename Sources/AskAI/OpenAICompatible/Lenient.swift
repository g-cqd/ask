/// A value a server may have sent as something else. Anything that is not a `Value` (a string for a number, a list for an
/// object, a null, a number that is not whole) is nil here, which costs the one field and not the response around it.
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
