/// The `@server:` picker (roadmap 0067): a server's resources, which the conversation lists as the choices of `@server`, asked for once
/// and again once stale. What is chosen replaces the word as `@server:uri`, read when the message is sent. A name that is no server with
/// resources, and a file's line range (`@file:12-30`), leave the word to the file picker.
extension ScreenController {
    /// The `@` word the cursor is in when it reads `name:` and what follows is not a line range, with the name.
    func resourceTrigger() -> (server: String, trigger: CompletionTrigger)? {
        guard let trigger = fileTrigger(), let colon = trigger.query.firstIndex(of: ":") else { return nil }
        let server = trigger.query[..<colon]
        let rest = trigger.query[trigger.query.index(after: colon)...]
        guard !server.isEmpty, server.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
            rest.isEmpty || !rest.allSatisfy({ $0.isNumber || $0 == "-" })
        else { return nil }
        return (String(server), trigger)
    }

    /// Opens or narrows the resource picker, asking the server's list when it is missing or old.
    /// - Returns: the effects; the file picker's too when the name has no resources, or its list is still coming and nothing after the
    ///   colon says a resource is meant.
    mutating func refreshResourcePicker(
        _ server: String,
        _ trigger: CompletionTrigger,
        screenRows: Int,
        at now: ContinuousClock.Instant
    ) -> [Effect] {
        let key = "@" + server
        // What was typed after `server:`, which the rows are ranked by: each row's label starts with what is before it.
        let rest = String(trigger.query.dropFirst(server.count + 1))
        var effects: [Effect] = []
        let held = state.choices[key]
        if held.map({ $0.stale || now - $0.at > Self.choicesMaxAge }) ?? true, !asking.contains(key) {
            asking.insert(key)
            effects = [.listChoices(command: key)]
        }
        guard let held, !held.rows.isEmpty else {
            // Nothing known yet: say it is being asked once a URI is being typed; until then `@file:` keeps the file picker, after the ask.
            guard held == nil, !rest.isEmpty else {
                return effects + refreshFilePicker(trigger, screenRows: screenRows, at: now)
            }
            install(waiting(server, trigger, screenRows))
            return effects
        }
        let rows = PickerRanking.rank(held.rows, query: rest)
        installWords(
            rows,
            kind: .resources(server: server),
            trigger: trigger,
            word: "@" + trigger.query,
            screenRows: screenRows,
            caption: held.rows.count > rows.count ? "\(rows.count) of \(held.rows.count)" : ""
        )
        return effects
    }

    private func waiting(_ server: String, _ trigger: CompletionTrigger, _ screenRows: Int) -> CompletionPicker {
        CompletionPicker(
            kind: .resources(server: server),
            trigger: trigger,
            matches: [],
            capacity: CompletionPicker.capacity(screenRows: screenRows),
            caption: "asking \(server)…"
        )
    }
}
