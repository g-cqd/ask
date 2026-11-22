internal import AskCodemode
internal import AskMCP
internal import Foundation
internal import Synchronization

/// The Python a codemode script runs on (ADR-0156): the first `python3` on the `PATH` (the owner, 2026-11-16), in a process
/// that can reach its own interpreter and nothing else.
///
/// JavaScriptCore has no way out of its VM but what it is handed. Python has the whole language: files, sockets, other
/// programs. So "a script's only capability is the tools" is, for Python, the profile its process runs under: everything denied,
/// then the interpreter and the system's libraries allowed to be read. Nothing of the person's can be read, nothing written,
/// no network, no fork. Measured on its first version: every attempt a `PermissionError`, for 6 ms a script.
enum CodemodePython {
    /// An interpreter as it really is on disk: where a `python3` leads, links followed.
    struct Interpreter: Sendable, Equatable {
        /// The program that runs.
        let executable: String
        /// Where its standard library and its own libraries are: `sys.base_prefix` and `sys.base_exec_prefix`.
        let roots: [String]
    }

    /// What asks a Python where it is. Isolated (`-I`, `-S`): it reads no variable, no user site, no startup file.
    private static let whereItIs =
        "import os, sys\nfor p in (sys.executable, sys.base_prefix, sys.base_exec_prefix): print(os.path.realpath(p))"

    /// The first `python3` on `path`.
    static func first(onPath path: String?) -> String? { CommandCheck.executable("python3", path: path) }

    /// What the question runs under, for a `python3` that is not the system's (security audit 2026-11-22, HIGH-09): it may read,
    /// to find itself, and run what it is (a version manager's shim runs the real one), but write nothing and reach no network, so a
    /// `python3` planted on the `PATH` learns nothing it can keep and does nothing before ask has looked at its answer.
    static let questionProfile =
        "(version 1)(deny default)(allow file-read*)(allow process-exec*)(allow process-fork)(allow file-map-executable)"
        + "(allow sysctl-read)"

    /// Asks `python` where it really is; nil when it does not answer as a Python does, or names a root that would let a script read
    /// the person's files: `/`, their home, or a folder above it.
    static func interpreter(_ python: String, home: String = NSHomeDirectory()) async -> Interpreter? {
        let question = ["-I", "-S", "-c", whereItIs]
        // The system's own `python3` (root's, in a folder only root writes) is asked as it is: Xcode's shim writes a cache, which
        // the question's profile refuses. Any other is asked under that profile.
        let asked =
            isSystemOwned(python)
            ? await CommandCheck.run(python, question, environment: [:], deadline: .seconds(10))
            : await CommandCheck.run(
                "/usr/bin/sandbox-exec",
                ["-p", questionProfile, python] + question,
                environment: [:],
                deadline: .seconds(10)
            )
        guard case .ran(let ran) = asked, ran.status == 0 else { return nil }
        let paths = ran.output.split(separator: "\n").map(String.init)
        guard paths.count == 3, paths.allSatisfy({ $0.hasPrefix("/") }) else { return nil }
        var roots: [String] = []
        for root in paths.dropFirst() where !roots.contains(root) { roots.append(root) }
        let realHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        guard roots.allSatisfy({ $0 != "/" && $0 != realHome && !realHome.hasPrefix($0 + "/") }) else { return nil }
        return Interpreter(executable: paths[0], roots: roots)
    }

    /// Whether `program`, links followed, and the folder it is in belong to root and nobody else may write them.
    static func isSystemOwned(_ program: String) -> Bool {
        let real = URL(fileURLWithPath: program).resolvingSymlinksInPath().path
        return [real, (real as NSString).deletingLastPathComponent]
            .allSatisfy { path in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                    let owner = attributes[.ownerAccountID] as? NSNumber,
                    let mode = attributes[.posixPermissions] as? NSNumber
                else { return false }
                return owner.intValue == 0 && mode.intValue & 0o022 == 0
            }
    }

    /// The profile a script's Python runs under, as `sandbox-exec`'s arguments: its text, and the paths it names as parameters
    /// (`-D NAME=path`), never as text of the profile (ADR-0020).
    static func profile(for interpreter: Interpreter) -> (text: String, arguments: [String]) {
        var arguments = ["-D", "EXECUTABLE=\(interpreter.executable)"]
        let roots = named(interpreter.roots, "ROOT", as: "subpath", into: &arguments)
        // The loader walks down to the interpreter: each directory above it may be looked at, not listed.
        var above: [String] = []
        for path in interpreter.roots + [interpreter.executable] {
            var parent = (path as NSString).deletingLastPathComponent
            while parent != "/", !parent.isEmpty, !above.contains(parent) {
                above.append(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        let looked = named(above.sorted(), "ABOVE", as: "literal", into: &arguments)
        let system =
            #"(subpath "/usr/lib") (subpath "/System/Library") (subpath "/System/Cryptexes")"#
            + #" (subpath "/System/Volumes/Preboot/Cryptexes")"#
        let text = """
            (version 1)
            (deny default)
            (allow process-exec (literal (param "EXECUTABLE")) \(roots))
            (allow file-read* \(roots) \(system) (subpath "/private/var/db/dyld") (literal "/dev/null") (literal "/dev/urandom"))
            (allow file-read* (literal "/private/etc/localtime") (subpath "/private/var/db/timezone") (subpath "/usr/share/zoneinfo"))
            (allow file-read-data file-read-metadata (literal "/"))
            (allow file-read-metadata \(looked))
            (allow file-map-executable \(roots) \(system))
            """
        return (text, arguments)
    }

    /// The profile's words for `paths`, each a parameter `PREFIXn` defined in `arguments`: `(kind (param "PREFIX0")) …`.
    private static func named(_ paths: [String], _ prefix: String, as kind: String, into arguments: inout [String])
        -> String
    {
        paths.enumerated()
            .map { index, path -> String in
                arguments += ["-D", "\(prefix)\(index)=\(path)"]
                return #"(\#(kind) (param "\#(prefix)\#(index)"))"#
            }
            .joined(separator: " ")
    }

    /// What starts a script's Python: `python`, as it really is, under its profile, given the prelude and its memory limit.
    /// What it learns of the interpreter it learns once. No Python there, or one that will not say where it is, starts nothing.
    static func child(_ python: String) -> CodemodeChild.Start {
        let known = Mutex<Interpreter?>(nil)
        return { memoryMiB in
            var interpreter = known.withLock { $0 }
            if interpreter == nil {
                interpreter = await Self.interpreter(python)
                known.withLock { $0 = interpreter }
            }
            guard let interpreter else { return nil }
            let profile = profile(for: interpreter)
            let run = [interpreter.executable, "-I", "-S", "-c", CodemodePythonPrelude.source, "\(memoryMiB)"]
            let launch = StdioLaunch(
                executable: "/usr/bin/sandbox-exec",
                arguments: profile.arguments + ["-p", profile.text] + run,
                inheriting: [:]
            )
            return await CodemodeChild.launched(launch, watched: true)
        }
    }
}
