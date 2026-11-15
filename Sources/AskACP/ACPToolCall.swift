internal import AemiJSON
internal import AskTUI

/// A tool call as ACP shows it (ACP v1, Tool Calls), from what the conversation says of it: the block the screen draws.
///
/// The conversation says a call's name as the screen shows it (a command's is its shell's), a line about its input and its input
/// in full as text; not the input as the model wrote it. So a call here has a title, a kind, the file it names and its text,
/// a command's `rawInput`, and no diff of an edit.
enum ACPToolCall {
    /// A call as the conversation says it began.
    struct Begun {
        let id: String
        let name: String
        let summary: String
        let fullInput: String
        let isCommand: Bool
        let path: String?
    }

    /// `tool_call`: a call began, in the session whose folder is `folder`. A command's title is its first line; any other's is
    /// the screen's header for it.
    static func started(_ call: Begun, in folder: String) -> (title: String, update: JSONValue) {
        let title =
            call.isCommand
            ? firstLine(of: call.fullInput) : (call.summary.isEmpty ? call.name : "\(call.name) \(call.summary)")
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "tool_call", "toolCallId": .string(call.id), "title": .string(title),
            "name": .string(call.name),
            "kind": .string(call.isCommand ? "execute" : kind(of: call.name)), "status": "in_progress"
        ]
        if let path = call.path {
            update["locations"] = [["path": .string(path.hasPrefix("/") ? path : folder + "/" + path)]]
        }
        if call.isCommand {
            update["rawInput"] = ["command": .string(call.fullInput)]
        } else if !call.fullInput.isEmpty {
            update["content"] = [text(call.fullInput)]
        }
        return (title, .object(update))
    }

    /// `tool_call_update`: the call ended, with what it returned; and with its `title` again, when its progress had been on it.
    static func finished(id: String, _ status: Transcript.ToolStatus, output: String, title: String? = nil) -> JSONValue
    {
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
        if !output.isEmpty { update["content"] = [text(output)] }
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
