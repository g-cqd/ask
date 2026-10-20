/// One persisted line. Internal so the wire format can evolve independently of the domain types.
///
/// Shapes, keys sorted on encode:
/// `{"type":"session","version":1}`, `{"id":…,"parent":…,"payload":{…},"type":"entry"}`,
/// `{"id":…|null,"type":"leaf"}`, `{"network":…,"type":"sandbox","write":[…]}`.
enum SessionLogRecord: Sendable, Equatable {
    case header(version: Int)
    case entry(SessionEntry)
    /// A checkout. Without one, replay leaves the leaf at the most recent entry, as `append` does.
    case leaf(EntryID?)
    /// The strict sandbox the session runs under from here on: its write scopes and network level only.
    case sandbox(SandboxSection)
}

extension SessionLogRecord: Codable {
    private enum CodingKeys: String, CodingKey { case type, version, id, parent, payload }
    /// The sandbox record's own key set, so every other line matches no more keys than before. It repeats `type` so
    /// the record is written through one container: one encoder, one keyed container.
    private enum SandboxKeys: String, CodingKey { case type, write, read, network }
    private enum Kind: String, Codable { case session, entry, leaf, sandbox }

    /// A write or read scope on the wire: `"workspace"`, `"anywhere"`, or an array of paths.
    private struct WireScope: Codable {
        let setting: PathSetting

        init(_ setting: PathSetting) { self.setting = setting }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let paths = try? container.decode([String].self) {
                setting = .paths(paths)
                return
            }
            switch try container.decode(String.self) {
                case "workspace": setting = .workspace
                case "anywhere": setting = .anywhere
                default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown write scope")
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch setting {
                case .workspace: try container.encode("workspace")
                case .anywhere: try container.encode("anywhere")
                case .paths(let paths): try container.encode(paths)
            }
        }
    }

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
            case .sandbox:
                let fields = try decoder.container(keyedBy: SandboxKeys.self)
                let network = try fields.decodeIfPresent(String.self, forKey: .network)
                    .map { name throws in
                        guard let level = SandboxPolicy.Network(named: name) else {
                            throw DecodingError.dataCorruptedError(
                                forKey: .network, in: fields, debugDescription: "unknown network level")
                        }
                        return level
                    }
                self = .sandbox(
                    SandboxSection(
                        write: try fields.decode([WireScope].self, forKey: .write).map(\.setting),
                        read: try fields.decodeIfPresent([WireScope].self, forKey: .read)?.map(\.setting) ?? [],
                        network: network))
        }
    }

    func encode(to encoder: any Encoder) throws {
        if case .sandbox(let section) = self {
            // @dl:accept -- explicit coding keeps the session format ours (ADR-0013); one container per record (AemiJSON #4)
            var fields = encoder.container(keyedBy: SandboxKeys.self)
            try fields.encode(Kind.sandbox, forKey: .type)
            try fields.encode(section.write.map(WireScope.init), forKey: .write)
            // Absent when unset, so a session without a read scope writes the record as before.
            if !section.read.isEmpty { try fields.encode(section.read.map(WireScope.init), forKey: .read) }
            try fields.encodeIfPresent(section.network?.description, forKey: .network)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        // @dl:accept -- explicit coding keeps the session format ours, not Swift's synthesized shape (ADR-0013)
        switch self {
            case .header(let version):
                try container.encode(Kind.session, forKey: .type)
                try container.encode(version, forKey: .version)
            case .entry(let entry):
                try container.encode(Kind.entry, forKey: .type)
                try container.encode(entry.id.description, forKey: .id)
                try container.encodeIfPresent(entry.parentID?.description, forKey: .parent)
                try container.encode(WirePayload(value: entry.payload), forKey: .payload)
            case .sandbox: break  // written above
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
