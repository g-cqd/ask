internal import AemiJSON
internal import AskAI

extension ConfigEditor {
    /// The editor's rows, from the settings catalog (roadmap 0096): the `ui` section first, as the setting most often changed here, then
    /// the rest in the catalog's order, then the MCP servers as one row. Switches and choices can change; the rest are shown so a person
    /// sees they exist.
    static let descriptors: [Descriptor] =
        (SettingCatalog.all.filter { $0.path[0] == "ui" } + SettingCatalog.all.filter { $0.path[0] != "ui" })
        .map { setting in
            let kind: Descriptor.Kind =
                switch setting.kind {
                    case .boolean: .boolean
                    case .choice(let words): .choice(words)
                    case .integer, .text, .structured: .readOnly
                }
            return Descriptor(path: setting.path, kind: kind)
        } + [Descriptor(path: ["mcp"], kind: .readOnly)]

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
