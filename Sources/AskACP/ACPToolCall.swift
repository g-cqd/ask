internal import AemiJSON
internal import AskTUI

/// A tool call as ACP shows it (ACP v1, Tool Calls), from what the conversation says of it: the block the screen draws.
///
/// The conversation says a call's name as the screen shows it (a command's is its shell's), a line about its input, its input in
/// full as text, and the input as the model wrote it. So a call here has a title, a kind, the file it names, its `rawInput`, and
/// either its text or, for a change to a file, a diff.
enum ACPToolCall {
    /// A call as the conversation says it began.
    struct Begun {
        let id: String
        let name: String
        let summary: String
        let fullInput: String
        let isCommand: Bool
        let path: String?
        /// The input as the model wrote it, a JSON object's bytes; empty for a call that is not the model's.
        var rawInput: [UInt8] = []
    }

    /// A call as ACP is told it began: the `tool_call`, the title it was given, and the change it makes to a file, when it is
    /// one, which is said again when it ends.
    struct Started {
        let title: String
        let change: JSONValue?
        let update: JSONValue
    }

    /// `tool_call`: a call began, in the session whose folder is `folder`. A command's title is its first line; any other's is
    /// the screen's header for it.
    static func started(_ call: Begun, in folder: String) -> Started {
        let title =
            call.isCommand
            ? firstLine(of: call.fullInput) : (call.summary.isEmpty ? call.name : "\(call.name) \(call.summary)")
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "tool_call", "toolCallId": .string(call.id), "title": .string(title),
            "name": .string(call.name),
            "kind": .string(call.isCommand ? "execute" : kind(of: call.name)), "status": "in_progress"
        ]
        let location = call.path.map { $0.hasPrefix("/") ? $0 : folder + "/" + $0 }
        if let location { update["locations"] = [["path": .string(location)]] }
        let input = (try? AemiJSON.parse(call.rawInput))?.root
        let change = call.isCommand ? nil : location.flatMap { change(input, to: $0, by: call.name) }
        if let input, input.isObject {
            update["rawInput"] = JSONValue(input)
        } else if call.isCommand {
            // A command the person typed has no input of the model's: what it runs is its input.
            update["rawInput"] = ["command": .string(call.fullInput)]
        }
        if let change {
            update["content"] = [change]
        } else if !call.isCommand, !call.fullInput.isEmpty {
            update["content"] = [text(call.fullInput)]
        }
        return Started(title: title, change: change, update: .object(update))
    }

    /// The change a `write` or an `edit` makes to the file at `path`, as a diff (Tool Calls, "Diffs"): the text replaced and what
    /// replaces it, or a whole file's new content. A whole file is said with no old text, as a new one is, since what the file
    /// held is not known here: a client shows all of it as added.
    private static func change(_ input: JSON?, to path: String, by tool: String) -> JSONValue? {
        guard let input, kind(of: tool) == "edit" else { return nil }
        if let old = input["old_text"].string, let new = input["new_text"].string {
            return ["type": "diff", "path": .string(path), "oldText": .string(old), "newText": .string(new)]
        }
        guard let content = input["content"].string else { return nil }
        return ["type": "diff", "path": .string(path), "newText": .string(content)]
    }

    /// `tool_call_update`: the call ended, with what it returned; and with its `title` again, when its progress had been on it.
    /// A call's content is replaced by an update's, so the `change` a call made is said again before what it returned; one that
    /// failed made none.
    static func finished(
        id: String,
        _ status: Transcript.ToolStatus,
        output: String,
        title: String? = nil,
        change: JSONValue? = nil
    ) -> JSONValue {
        let said: JSONValue =
            switch status {
                case .succeeded: "completed"
                case .running: "in_progress"
                // A call the person stopped did not do its work: ACP's statuses have no word of their own for it.
                case .failed, .interrupted: "failed"
            }
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "tool_call_update", "toolCallId": .string(id)
        ]
        if let title { update["title"] = .string(title) }
        update["status"] = said
        var content: [JSONValue] = []
        if case .succeeded = status, let change { content.append(change) }
        if !output.isEmpty { content.append(text(output)) }
        if !content.isEmpty { update["content"] = .array(content) }
        return .object(update)
    }

    /// `tool_call_update` for a call that goes on: its title as it was, and that it runs, or only the title.
    static func resumed(id: String, title: String, running: Bool) -> JSONValue {
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "tool_call_update", "toolCallId": .string(id), "title": .string(title)
        ]
        if running { update["status"] = "in_progress" }
        return .object(update)
    }

    /// `tool_call_update`: how far the running call has got, said on its title as the screen says it on the block's header.
    static func progressed(id: String, title: String, progress: String) -> JSONValue {
        ["sessionUpdate": "tool_call_update", "toolCallId": .string(id), "title": .string("\(title) · \(progress)")]
    }

    /// ACP's category for ask's tool `name`, which a client picks an icon by; `other` for any it does not know (an MCP server's).
    /// A command is `execute` whatever its name, which is its shell's on the screen.
    static func kind(of name: String) -> String {
        switch name {
            case "read": "read"
            case "write", "edit": "edit"
            case "fetch": "fetch"
            case "search_session": "search"
            default: "other"
        }
    }

    /// Text as a tool call's content.
    static func text(_ text: String) -> JSONValue {
        ["type": "content", "content": ["type": "text", "text": .string(text)]]
    }

    private static func firstLine(of command: String) -> String {
        guard let end = command.firstIndex(where: \.isNewline) else { return command }
        return command[..<end] + " …"
    }
}
