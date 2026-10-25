/// The spellings of tool names that other harnesses use, and the ask tool each one means. Data, not code: a harness's vocabulary is one more row.
///
/// Lookup ignores case and punctuation, so `Read`, `read_file` and `readFile` are one entry. A name in no row, a wildcard (`apple-docs/*`) and a
/// namespaced name (`mcp__apple-docs`) have no ask tool, which is a normal answer.
public struct ToolAliasTable: Sendable, Equatable {
    private let aliases: [String: String]

    public init(_ rows: [String: [String]]) {
        var table: [String: String] = [:]
        for (tool, spellings) in rows {
            table[tool.canonicalKey.filter { $0.isLetter || $0.isNumber }] = tool
            for spelling in spellings { table[Self.normalized(spelling)] = tool }
        }
        aliases = table
    }

    /// The ask tool a spelling means, or nil.
    public func lookup(_ name: String) -> String? {
        if name.contains("*") || name.hasPrefix("mcp__") { return nil }
        return aliases[Self.normalized(name)]
    }

    private static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// ask's tools, and the other names seen for them in real harness files. Tools ask does not have yet (`grep`, `find`, `ls`, `skill`, `agent`) are
    /// here so a file written for them is understood the day they exist.
    public static let standard = ToolAliasTable([
        // @dl:accept -- a table of tool-name spellings: the rows are the data
        "read": ["read_file", "view_file", "view_file_outline", "view_code_item", "cat", "open", "view", "file_read"],
        "write": ["write_file", "write_to_file", "create", "create_file", "file_write"],
        "edit": [
            // @dl:accept -- a table of tool-name spellings: the rows are the data
            "multi_edit", "notebook_edit", "replace_file_content", "multi_replace_file_content", "str_replace",
            "str_replace_editor", "replace", "patch", "apply_patch",
            "edit_file"
        ],
        "bash": [
            "shell", "run_command", "execute", "exec", "terminal", "run", "sh", "command", "run_shell_command",
            "bash_command"
        ],
        "wait": ["bash_output", "job_output"],
        "job_input": ["send_command_input"],
        "job_stop": ["kill_shell", "kill_bash", "stop_job"],
        "narrow_sandbox": [],
        "grep": ["search", "grep_search", "ripgrep", "rg", "code_search", "search_files"],
        "find": ["glob", "find_by_name", "file_search", "list_files"],
        "ls": ["list", "list_dir", "list_directory"],
        "skill": ["skills", "use_skill"],
        "agent": [
            "task", "subagent", "dispatch_agent", "spawn_agent", "invoke_subagent", "manage_subagents",
            "define_subagent"
        ]
    ])
}
