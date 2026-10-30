internal import AemiJSON

/// The setting names roadmap 0154 replaced, read as the new ones: a file written before still loads, and each old name is reported once
/// with its new name. A new name set beside its old one wins, and the old one is reported as ignored. Each key keeps its place in the
/// file.
enum SettingRenames {
    typealias Object = OrderedDictionary<String, JSONValue>

    /// One key renamed inside its section: where it goes (one or two keys deep) and what its value becomes.
    struct Rename: Sendable {
        let section: String
        let old: String
        let new: [String]
        /// The value under the new name, or nil when the old value is not one the old name took.
        let value: @Sendable (JSONValue) -> JSONValue?
    }

    /// `true` or `"on"` as true, `false` or `"off"` as false, anything else as nil (the decoder then reports it under the new name).
    static func switchValue(_ value: JSONValue) -> Bool? {
        switch value {
            case .bool(let on): on
            case .string("on"): true
            case .string("off"): false
            default: nil
        }
    }

    private static func same(_ value: JSONValue) -> JSONValue { value }

    private static func folded(_ value: JSONValue) -> JSONValue? {
        switch value {
            case .string("folded"): .bool(true)
            case .string("open"): .bool(false)
            default: nil
        }
    }

    private static let table: [Rename] = [
        // @dl:accept -- the rename table is data: each row names an old key, its new place and its value
        Rename(section: "ui", old: "promptRows", new: ["inputRows"], value: same),
        Rename(section: "ui", old: "prompt", new: ["inputPrefix"], value: same),
        Rename(section: "ui", old: "tools", new: ["fold", "tools"], value: folded),
        Rename(section: "ui", old: "thinking", new: ["fold", "thinking"], value: folded),
        Rename(section: "ui", old: "code", new: ["fold", "code"], value: folded),
        Rename(section: "ui", old: "codeFoldLines", new: ["fold", "codeLines"], value: same),
        Rename(section: "ui", old: "localizedDurations", new: ["durations"]) { value in
            // @dl:accept -- the rename table is data: each row names an old key, its new place and its value
            switchValue(value).map { .string($0 ? "words" : "clock") }
        },
        Rename(section: "ui", old: "timeout", new: ["showTimeout"], value: same),
        Rename(section: "ui", old: "interruptKeys", new: ["stopKeys"], value: same),
        Rename(section: "ui", old: "interruptSendsQueued", new: ["queuedOnStop"], value: same),
        Rename(section: "ui", old: "jobAutoReturnWhenFocused", new: ["leaveFinishedJob"], value: same),
        Rename(section: "ui", old: "onlyUsefulModels", new: ["listAllModels"]) { value in
            switchValue(value).map { .bool(!$0) }
        },
        Rename(section: "sandbox", old: "denyRead", new: ["hide"], value: same),
        Rename(section: "sandbox", old: "allowRead", new: ["readable"], value: same),
        Rename(section: "sandbox", old: "allowWrite", new: ["writable"], value: same),
        Rename(section: "approvals", old: "scope", new: ["remember"]) { value in
            value == .string("narrowing-only") ? .string("narrowing") : value
        },
        Rename(section: "skills", old: "maxAdvertised", new: ["maxListed"], value: same)
    ]

    /// The old `ui` switches that `ui.stopTwice` replaced, each with the key it named and its default.
    private static let stopSwitches = [
        ("escapeInterruptRequiresConfirmation", "esc", true), ("abortTurnRequiresConfirmation", "ctrl-c", false)
    ]

    /// `root` with every old name replaced by its new one, and a sentence per old name found.
    /// - Throws: ``ConfigurationFile/BadValue`` naming the old key, for a value the old name did not take.
    static func apply(to root: JSONValue) throws -> (value: JSONValue, notices: [String]) {
        guard case .object(var top) = root else { return (root, []) }
        var notices: [String] = []
        for section in ["ui", "sandbox", "approvals", "skills"] {
            guard case .object(var object)? = top[section] else { continue }
            for rename in table where rename.section == section {
                try move(rename, in: &object, notices: &notices)
            }
            if section == "ui" { try stopTwice(in: &object, notices: &notices) }
            top[section] = .object(object)
        }
        keepAwake(in: &top, notices: &notices)
        return (.object(top), notices)
    }

    static func renamed(_ old: String, _ new: String) -> String {
        "`\(old)` is now `\(new)`; ask reads the old name for now."
    }

    static func ignored(_ old: String, _ new: String) -> String { "`\(old)` is ignored: `\(new)` is set too." }

    private static func move(_ rename: Rename, in object: inout Object, notices: inout [String]) throws {
        guard let index = object.index(forKey: rename.old) else { return }
        let old = rename.section + "." + rename.old
        guard let value = rename.value(object.values[index]) else {
            throw ConfigurationFile.BadValue(key: old, value: described(object.values[index]))
        }
        object.remove(at: index)
        let new = ([rename.section] + rename.new).joined(separator: ".")
        guard rename.new.count == 2 else {
            if object[rename.new[0]] != nil { return notices.append(ignored(old, new)) }
            object.updateValue(value, forKey: rename.new[0], insertingAt: index)
            return notices.append(renamed(old, new))
        }
        var inner: Object = if case .object(let existing)? = object[rename.new[0]] { existing } else { [:] }
        if inner[rename.new[1]] != nil { return notices.append(ignored(old, new)) }
        inner[rename.new[1]] = value
        let position = object.index(forKey: rename.new[0]) ?? Swift.min(index, object.count)
        object.removeValue(forKey: rename.new[0])
        object.updateValue(.object(inner), forKey: rename.new[0], insertingAt: Swift.min(position, object.count))
        notices.append(renamed(old, new))
    }

    /// The two confirmation switches as the list of keys that must be pressed twice to stop a turn.
    private static func stopTwice(in object: inout Object, notices: inout [String]) throws {
        let found = stopSwitches.compactMap { name, key, on in object.index(forKey: name).map { ($0, name, key, on) } }
        guard let first = found.map(\.0).min() else { return }
        let keepNew = object["stopTwice"] != nil
        var keys: [JSONValue] = []
        for (name, key, fallback) in stopSwitches {
            if let given = object[name], switchValue(given) == nil {
                throw ConfigurationFile.BadValue(key: "ui." + name, value: described(given))
            }
            let on = object[name].flatMap(switchValue) ?? fallback
            if on { keys.append(.string(key)) }
            if object[name] != nil {
                notices.append(keepNew ? ignored("ui." + name, "ui.stopTwice") : renamed("ui." + name, "ui.stopTwice"))
            }
            object.removeValue(forKey: name)
        }
        if !keepNew {
            object.updateValue(.array(keys), forKey: "stopTwice", insertingAt: Swift.min(first, object.count))
        }
    }

    /// A value as an error quotes it.
    private static func described(_ value: JSONValue) -> String {
        if case .string(let text) = value { return text }
        return String(decoding: (try? value.encodedBytes()) ?? [], as: UTF8.self)
    }

    /// `keepAwake: "system"` is `"working"`; `"display"` is `"working"` with `keepDisplayAwake: true`.
    private static func keepAwake(in top: inout Object, notices: inout [String]) {
        guard let index = top.index(forKey: "keepAwake"), case .string(let word) = top.values[index] else { return }
        guard word == "system" || word == "display" else { return }
        top.updateValue(.string("working"), forKey: "keepAwake")
        if word == "display", top["keepDisplayAwake"] == nil {
            top.updateValue(.bool(true), forKey: "keepDisplayAwake", insertingAt: index + 1)
            return notices.append(
                "`keepAwake: \"display\"` is now `keepAwake: \"working\"` with `keepDisplayAwake: true`; ask reads the old value for now."
            )
        }
        notices.append(renamed("keepAwake: \"\(word)\"", "keepAwake: \"working\""))
    }
}
