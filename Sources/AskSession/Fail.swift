internal import Foundation

/// Ends the process with `message` on standard error and `code`.
package func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
