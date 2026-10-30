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
                .init(path: ["keepAwake"], kind: .choice(KeepAwakeMode.allCases.map(\.rawValue))),
                .init(path: ["keepDisplayAwake"], kind: .boolean),
                .init(path: ["credentials"], kind: .choice(CredentialStorage.allCases.map(\.rawValue))),
                // @dl:accept -- editor rows are data: a path and a kind each
                readOnly(["sandbox", "readable"]), readOnly(["sandbox", "writable"]), readOnly(["sandbox", "hide"]),
                // @dl:accept -- read-only rows across sections list real configuration keys; the lists are the data
                readOnly(["sandbox", "write"]), readOnly(["sandbox", "read"]),
                .init(path: ["sandbox", "network"], kind: .choice(["none", "localhost", "any"])),
                .init(path: ["approvals", "default"], kind: .choice(["ask", "allow"])),
                readOnly(["approvals", "allow"]), readOnly(["approvals", "ask"]),
                .init(path: ["approvals", "remember"], kind: .choice(ApprovalsSection.Scope.allCases.map(\.rawValue))),
                .init(path: ["skills", "enabled"], kind: .boolean),
                readOnly(["skills", "maxListed"]), readOnly(["skills", "sources"]),
                readOnly(["mcp"]), readOnly(["environment", "pass"]), readOnly(["environment", "withhold"]),
                readOnly(["environment", "shell"])
            ]
        return rows
    }()

    /// A read-only row at `path`.
    private static func readOnly(_ path: [String]) -> Descriptor { .init(path: path, kind: .readOnly) }

    /// A read-only row at top-level key `name`.
    private static func readOnly(_ name: String) -> Descriptor { readOnly([name]) }

    /// The `ui` section's rows (roadmap 0154): the switches as booleans, the fold switches under `ui.fold`, then the rest.
    // @dl:accept -- the `ui` key table is data: its rows differ only in their paths and choice lists
    private static let uiDescriptorTable: [Descriptor] =
        ["mouse", "copyOnSelect", "tint", "separator", "padding", "markdown", "leaveFinishedJob", "listAllModels"]
        .map { .init(path: ["ui", $0], kind: .boolean) }
        + ["tools", "thinking", "code"].map { .init(path: ["ui", "fold", $0], kind: .boolean) }
        + [
            readOnly(["ui", "fold", "codeLines"]), readOnly(["ui", "scrollLines"]), readOnly(["ui", "inputRows"]),
            .init(path: ["ui", "sidebar"], kind: .choice(["open", "closed"])),
            readOnly(["ui", "inputPrefix"]),
            .init(path: ["ui", "durations"], kind: .choice(["words", "clock"])),
            // @dl:accept -- one row per choice key, each naming its own enumeration; the rows are data
            .init(path: ["ui", "spinner"], kind: .choice(SpinnerPreference.allCases.map(\.rawValue))),
            .init(path: ["ui", "appearance"], kind: .choice(AppearancePreference.allCases.map(\.rawValue))),
            .init(path: ["ui", "stopKeys"], kind: .choice(InterruptKeysPreference.allCases.map(\.rawValue))),
            readOnly(["ui", "stopTwice"]),
            .init(path: ["ui", "showTimeout"], kind: .choice(TimeoutPreference.allCases.map(\.rawValue))),
            readOnly(["ui", "timeoutLabel"]),
            .init(path: ["ui", "queuedOnStop"], kind: .choice(QueuedAfterInterruptPreference.allCases.map(\.rawValue)))
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
