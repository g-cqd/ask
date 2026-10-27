internal import AemiJSON
internal import AskAI

extension ConfigEditor {
    /// The settings the interactive editor can change, and the ones it shows so a person can see they exist.
    // @dl:accept -- a table of setting paths and kinds; the entries are the data, and they read alike because every row has a path and a kind
    static let descriptors: [Descriptor] = {
        var rows: [Descriptor] =
            uiDescriptorTable + [
                readOnly("model"), readOnly("provider"),
                .init(path: ["thinking"], kind: .choice(ThinkingLevel.allCases.map(\.rawValue))),
                readOnly("maxTurns"), readOnly("compactAt"),
                readOnly(["sandbox", "allowRead"]), readOnly(["sandbox", "denyRead"]),
                // @dl:accept -- read-only rows across sections list real configuration keys; the lists are the data
                readOnly(["sandbox", "write"]), readOnly(["sandbox", "read"]),
                .init(path: ["sandbox", "network"], kind: .choice(["none", "localhost", "any"])),
                .init(path: ["skills", "enabled"], kind: .boolean),
                readOnly(["skills", "maxAdvertised"]), readOnly(["skills", "sources"]),
                readOnly(["mcp"]), readOnly(["environment", "pass"]), readOnly(["environment", "withhold"])
            ]
        return rows
    }()

    /// A read-only row at `path`.
    private static func readOnly(_ path: [String]) -> Descriptor { .init(path: path, kind: .readOnly) }

    /// A read-only row at top-level key `name`.
    private static func readOnly(_ name: String) -> Descriptor { readOnly([name]) }

    /// The `ui` section's rows: two wire booleans, six on/off strings, three folded/open switches, then the rest.
    // @dl:accept -- the `ui` key table is data: its three switch spellings differ only in their choice lists
    private static let uiDescriptorTable: [Descriptor] =
        ["mouse", "copyOnSelect"].map { .init(path: ["ui", $0], kind: .boolean) }
        + [
            "tint", "separator", "padding", "localizedDurations", "jobAutoReturnWhenFocused",
            "abortTurnRequiresConfirmation"
        ]
        .map { .init(path: ["ui", $0], kind: .onOff) }
        + ["tools", "thinking", "code"]
        .map {
            .init(path: ["ui", $0], kind: .choice(["folded", "open"]))
        }
        + [
            readOnly(["ui", "scrollLines"]), readOnly(["ui", "promptRows"]),
            .init(path: ["ui", "sidebar"], kind: .choice(["open", "closed"])),
            readOnly(["ui", "prompt"]),
            .init(path: ["ui", "spinner"], kind: .choice(SpinnerPreference.allCases.map(\.rawValue)))
        ]

    /// One descriptor as a row: its current value, and `unset` plus the choices when it can change.
    static func setting(_ descriptor: Descriptor, in root: JSONValue) -> Setting {
        let title = descriptor.path.joined(separator: ".")
        let current = Self.value(at: descriptor.path, in: root)
        switch descriptor.kind {
            case .boolean, .onOff:
                let wire = descriptor.kind == .boolean ? Wire.boolean : Wire.string
                return Setting(
                    path: descriptor.path, title: title, value: Self.onOff(current) ?? "invalid",
                    choices: ["unset", "on", "off"], editable: true, wire: wire)
            case .choice(let choices):
                let text = if case .string(let value) = current { value } else { "unset" }
                return Setting(
                    path: descriptor.path, title: title, value: text,
                    choices: ["unset"] + choices, editable: true)
            case .readOnly:
                return Setting(
                    path: descriptor.path, title: title, value: Self.display(current), choices: [], editable: false,
                    wire: .string)
        }
    }

    /// The value at `path`, or nil when any component is absent.
    static func value(at path: [String], in root: JSONValue) -> JSONValue? {
        var current = root
        for component in path {
            guard case .object(let object) = current, let next = object[component] else { return nil }
            current = next
        }
        return current
    }

    /// A setting's stored value as the row shows it.
    private static func display(_ value: JSONValue?) -> String {
        guard let value else { return "unset" }
        switch value {
            case .bool(let on): return on ? "on" : "off"
            case .string(let text): return text
            case .int(let number): return String(number)
            case .number(let number): return String(number)
            default: return String(decoding: (try? value.encodedBytes()) ?? [], as: UTF8.self)
        }
    }

    private static func onOff(_ value: JSONValue?) -> String? {
        switch value {
            case nil: "unset"
            case .bool(let on): on ? "on" : "off"
            case .string(let text) where text == "on" || text == "off": text
            default: nil
        }
    }
}
