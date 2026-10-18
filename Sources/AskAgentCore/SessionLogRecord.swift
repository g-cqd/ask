/// One persisted line. Internal so the wire format can evolve independently of the domain types.
///
/// Shapes, keys sorted on encode:
/// `{"type":"session","version":1}`, `{"id":…,"parent":…,"payload":{…},"type":"entry"}`,
/// `{"id":…|null,"type":"leaf"}`.
enum SessionLogRecord: Sendable, Equatable {
    case header(version: Int)
    case entry(SessionEntry)
    /// A checkout. Without one, replay leaves the leaf at the most recent entry, as `append` does.
    case leaf(EntryID?)
}

extension SessionLogRecord: Codable {
    private enum CodingKeys: String, CodingKey { case type, version, id, parent, payload }
    private enum Kind: String, Codable { case session, entry, leaf }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
            case .session:
                self = .header(version: try container.decode(Int.self, forKey: .version))
            case .entry:
                self = .entry(
                    SessionEntry(
                        id: EntryID(try container.decode(String.self, forKey: .id)),
                        parentID: try container.decodeIfPresent(String.self, forKey: .parent).map(EntryID.init),
                        payload: try container.decode(WirePayload.self, forKey: .payload).value))
            case .leaf:
                self = .leaf(try container.decodeIfPresent(String.self, forKey: .id).map(EntryID.init))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .header(let version):
                try container.encode(Kind.session, forKey: .type)
                try container.encode(version, forKey: .version)
            case .entry(let entry):
                try container.encode(Kind.entry, forKey: .type)
                try container.encode(entry.id.description, forKey: .id)
                try container.encodeIfPresent(entry.parentID?.description, forKey: .parent)
                try container.encode(WirePayload(value: entry.payload), forKey: .payload)
            case .leaf(let id):
                try container.encode(Kind.leaf, forKey: .type)
                // An explicit null, so "start a new root" is distinguishable from a missing key.
                if let id {
                    try container.encode(id.description, forKey: .id)
                } else {
                    try container.encodeNil(forKey: .id)
                }
        }
    }
}
