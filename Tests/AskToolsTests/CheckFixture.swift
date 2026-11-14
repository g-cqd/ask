import Foundation

/// A shell and a shellcheck that are scripts, in a folder of their own, so a test can see when and how often the check runs them:
/// `bash` here writes its first argument (`-n` for a parse, `-c` for a run) to `log`, then does what `/bin/bash` would.
struct CheckFixture {
    let directory: URL
    var shell: String { directory.appendingPathComponent("bash").path }
    /// A PATH where the fixture's shellcheck is the one found.
    var path: String { directory.path + ":/usr/bin:/bin" }

    /// - Parameters:
    ///   - beforeParse: shell commands the fake shell runs before a parse.
    ///   - shellcheck: the body of the fake shellcheck, which reads the command on its input; nil for none on the PATH.
    /// - Throws: when the folder or a script cannot be written.
    init(beforeParse: String = "", shellcheck: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let here = directory.path
        try write(
            "bash",
            """
            #!/bin/sh
            echo "$1" >> "\(here)/log"
            if [ "$1" = -n ]; then
            :
            \(beforeParse)
            fi
            exec /bin/bash "$@"
            """
        )
        if let shellcheck {
            try write("shellcheck", "#!/bin/sh\necho lint >> \"\(here)/log\"\n\(shellcheck)\n")
        }
    }

    private func write(_ name: String, _ script: String) throws {
        let file = directory.appendingPathComponent(name)
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    /// What ran, in order: `-n` a parse, `-c` a run, `lint` shellcheck.
    var log: [String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent("log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
