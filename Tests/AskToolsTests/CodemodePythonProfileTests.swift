import AskCodemode
import Foundation
import Testing

@testable import AskTools

/// What a Python script's process may reach (ADR-0156): its own interpreter and the system's libraries, read; nothing written,
/// no network, no other program. And what ask learns of an interpreter before it runs one.
@Suite("A Python script's profile allows its interpreter and nothing of the person's")
struct CodemodePythonProfileTests {
    private let interpreter = CodemodePython.Interpreter(
        executable: "/opt/py \"3\"/bin/python3.14",
        roots: ["/opt/py \"3\"", "/opt/py-exec"]
    )

    @Test func `it denies by default, and allows nothing to be written, connected to or forked`() {
        let profile = CodemodePython.profile(for: interpreter).text
        #expect(profile.hasPrefix("(version 1)\n(deny default)\n"))
        for operation in ["file-write", "network", "process-fork", "mach-lookup", "sysctl", "signal", "(allow default)"]
        {
            #expect(!profile.contains(operation), "\(operation)")
        }
    }

    @Test func `the interpreter's paths are parameters, never text of the profile`() {
        let (text, arguments) = CodemodePython.profile(for: interpreter)
        #expect(!text.contains("/opt/py"), "a path with a quote in it cannot end a string of the profile")
        let defined = stride(from: 0, to: arguments.count, by: 2).map { arguments[$0] + " " + arguments[$0 + 1] }
        #expect(defined.contains("-D EXECUTABLE=/opt/py \"3\"/bin/python3.14"))
        #expect(defined.contains("-D ROOT0=/opt/py \"3\"") && defined.contains("-D ROOT1=/opt/py-exec"))
        // Each of its ancestors may be looked at, not listed: the loader walks down to it.
        #expect(defined.contains("-D ABOVE0=/opt") && defined.contains("-D ABOVE1=/opt/py \"3\""))
        #expect(defined.contains("-D ABOVE2=/opt/py \"3\"/bin") && defined.count == 6)
        #expect(
            text.contains(
                #"(allow process-exec (literal (param "EXECUTABLE")) (subpath (param "ROOT0")) (subpath (param "ROOT1")))"#
            )
        )
        let looked =
            #"(allow file-read-metadata (literal (param "ABOVE0")) (literal (param "ABOVE1")) (literal (param "ABOVE2")))"#
        #expect(text.contains(looked))
    }

    @Test func `what it reads of the system is libraries and the time zone, by name`() {
        let text = CodemodePython.profile(for: interpreter).text
        #expect(text.contains(#"(subpath "/usr/lib") (subpath "/System/Library")"#))
        #expect(text.contains(#"(literal "/private/etc/localtime")"#))
        #expect(!text.contains(#""/System")"#) && !text.contains(#""/Users"#) && !text.contains(#""/private/etc")"#))
    }

    @Test(.enabled(if: PythonOnPath.first != nil, "no python3 on the PATH"))
    func `ask learns an interpreter's real paths by asking it once`() async throws {
        let python = try #require(PythonOnPath.first)
        let interpreter = try #require(await CodemodePython.interpreter(python))
        #expect(
            interpreter.executable.hasPrefix("/")
                && FileManager.default.isExecutableFile(atPath: interpreter.executable)
        )
        #expect(!interpreter.roots.isEmpty)
        for root in interpreter.roots {
            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) && isDirectory.boolValue,
                "\(root)"
            )
            #expect(URL(fileURLWithPath: root).resolvingSymlinksInPath().path == root, "resolved: \(root)")
        }
    }

    @Test func `what is not a Python gives no interpreter, and no python3 on the PATH is none`() async {
        #expect(await CodemodePython.interpreter("/usr/bin/true") == nil)
        #expect(await CodemodePython.interpreter("/no/such/python3") == nil)
        #expect(CodemodePython.first(onPath: "/no/such:/nor/this") == nil)
        #expect(CodemodePython.first(onPath: nil) == nil)
    }

    /// The Python prelude is text, and holds the output limits as numbers of its own: they are the VM's.
    @Test func `the Python prelude holds the limits the JavaScript VM has`() {
        #expect(CodemodePythonPrelude.source.contains("MAXIMUM_CHARACTERS = \(CodemodeVM.maximumCharacters)\n"))
        #expect(CodemodePythonPrelude.source.contains("MAXIMUM_ITEMS = \(CodemodeVM.maximumItems)\n"))
    }
}
