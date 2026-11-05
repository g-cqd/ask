internal import Darwin
internal import Foundation

/// A sign-in on the terminal ask was started from.
struct CommandLineInteraction: SignInInteraction {
    /// Written at once: `print` is buffered when stdout is a pipe, so a prompt written with it would wait for the sign-in it asks about.
    func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    func ask(_ prompt: String, secret: Bool) async -> String? {
        guard secret, isatty(STDIN_FILENO) == 1 else {
            say(prompt)
            return await Task.detached { readLine(strippingNewline: true) }.value
        }
        return await Task.detached { Self.hiddenLine(after: prompt) }.value
    }

    /// A line typed with echo off, restored afterwards. Echo goes off before `prompt` is shown, and neither change drops what was
    /// already typed (`TCSANOW`, not `TCSAFLUSH`): a password typed as soon as the prompt appeared was echoed, then thrown away, and
    /// ask waited for one that never came; three tries typed in quick succession lost each other the same way.
    private static func hiddenLine(after prompt: String) -> String? {
        let say = { (text: String) in FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            say(prompt)
            return readLine(strippingNewline: true)
        }
        var silent = original
        silent.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &silent)
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &original)
            say("")
        }
        say(prompt)
        return readLine(strippingNewline: true)
    }
}
