import AskAI
import AskAgentCore
import Foundation

/// A throwaway home directory with the things the default policy protects, a workspace, and the policy over them.
struct SandboxWorld {
    let home: String
    let workspace: String
    let config: String
    let state: String
    let policy: SandboxPolicy

    /// A world with these extra protections and allowances, relative to its home.
    /// - Parameters:
    ///   - extraDenyRead: directories under the home kept unreadable as well.
    ///   - allowRead: default protections lifted, relative to the home.
    ///   - outsideScratch: put the home in /Users/Shared rather than the temporary directory, which a
    ///     restricted-read policy keeps readable as scratch space; the caller removes it.
    /// - Throws: when the directories or files cannot be made.
    init(extraDenyRead: [String] = [], allowRead: [String] = [], outsideScratch: Bool = false) throws {
        let base = outsideScratch ? URL(filePath: "/Users/Shared") : FileManager.default.temporaryDirectory
        let made = base.appending(path: "ask-sandbox-\(UUID().uuidString)")
        for directory in [".config/ask", ".local/state/ask/sessions", ".aws", ".ssh", "work", "elsewhere"] {
            try FileManager.default.createDirectory(
                atPath: made.path + "/" + directory, withIntermediateDirectories: true)
        }
        let real = String(cString: realpath(made.path, nil))  // /var is a symlink to /private/var
        home = real
        workspace = real + "/work"
        config = real + "/.config/ask"
        state = real + "/.local/state/ask"
        for (path, text) in [
            (".config/ask/credentials.json", "sk-ant-secret"), (".config/ask/config.json", "{maxTurns: 5}"),
            (".aws/credentials", "aws-secret"), (".ssh/id_ed25519", "PRIVATE KEY"), (".ssh/config", "Host *"),
            (".local/state/ask/sessions/s.jsonl", "history"), ("work/file.txt", "workspace file")
        ] {
            try Data(text.utf8).write(to: URL(filePath: real + "/" + path))
        }
        policy = SandboxPolicy.standard(
            home: real, configDirectory: config, stateDirectory: state, allowRead: allowRead.map { real + "/" + $0 },
            denyRead: extraDenyRead.map { real + "/" + $0 })
    }

    var context: ToolContext { ToolContext(workingDirectory: workspace, sandbox: policy) }

    func text(_ relative: String) -> String? { try? String(contentsOfFile: home + "/" + relative, encoding: .utf8) }

    func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }
}
