import Foundation

@testable import AskTools

/// The Python the tests of codemode's Python surface run: the first `python3` on the `PATH`, as ask takes it; nil where there
/// is none, and those tests are then not run.
enum PythonOnPath {
    static let first = CodemodePython.first(onPath: ProcessInfo.processInfo.environment["PATH"])
    /// One child-starter for every test: what it learns of the interpreter, it learns once.
    static let start = CodemodePython.child(first ?? "/usr/bin/false")
}
