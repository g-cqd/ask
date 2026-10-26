internal import Darwin
internal import Foundation

/// A sign-in on the terminal ask was started from.
struct CommandLineInteraction: SignInInteraction {
    /// Written at once: `print` is buffered when stdout is a pipe, so a prompt written with it would wait for the sign-in it asks about.
    func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    func ask(_ prompt: String, secret: Bool) async -> String? {
        say(prompt)
        guard secret, isatty(STDIN_FILENO) == 1 else {
            return await Task.detached { readLine(strippingNewline: true) }.value
        }
        return await Task.detached { Self.hiddenLine() }.value
    }

    /// A line typed with echo off, restored afterwards.
    private static func hiddenLine() -> String? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return readLine(strippingNewline: true) }
        var silent = original
        silent.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &silent)
        defer {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        return readLine(strippingNewline: true)
    }
}
