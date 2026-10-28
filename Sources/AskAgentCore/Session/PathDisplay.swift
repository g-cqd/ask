public import Foundation

/// Formats paths for terminal display with tilde, clickable OSC 8 hyperlinks, and paste-safe shell arguments.
public enum PathDisplay {
    /// Formats an absolute path with a leading `~` if it lies within `home`.
    public static func tilde(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        let resolvedHome = URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath().path
        if path == resolvedHome { return "~" }
        if path.hasPrefix(resolvedHome + "/") {
            return "~" + path.dropFirst(resolvedHome.count)
        }
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        if resolvedPath == resolvedHome { return "~" }
        if resolvedPath.hasPrefix(resolvedHome + "/") {
            return "~" + resolvedPath.dropFirst(resolvedHome.count)
        }
        return path
    }

    /// Whether `text` holds a C0 control (ESC, BEL, newline, ...), DEL or a C1 control. Such a character printed to a
    /// terminal is interpreted, not shown, and a pasted command cannot carry it safely.
    public static func hasControl(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isControl)
    }

    /// `text` with every control character replaced by U+FFFD, so a path from the file system can be printed.
    public static func sanitized(_ text: String) -> String {
        guard hasControl(text) else { return text }
        var view = String.UnicodeScalarView()
        for scalar in text.unicodeScalars { view.append(isControl(scalar) ? "\u{FFFD}" : scalar) }
        return String(view)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F ... 0x9F).contains(scalar.value)
    }

    /// Formats an OSC 8 terminal hyperlink for a file path, with an absolute `file://` URI. A path or label holding a
    /// control character is printed as plain, sanitized text: no escape sequence is built from it.
    public static func link(to path: String, display: String? = nil) -> String {
        let label = display ?? tilde(path)
        if hasControl(path) || hasControl(label) { return sanitized(label) }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let encoded = URL(fileURLWithPath: resolved).absoluteString
        return "\u{1B}]8;;\(encoded)\u{1B}\\\(label)\u{1B}]8;;\u{1B}\\"
    }

    /// Formats an argument for safe copy-pasting into a shell (bash/zsh/fish), preserving leading `~` unquoted.
    public static func shellArgument(_ argument: String, home: String = NSHomeDirectory()) -> String {
        let display = tilde(argument, home: home)
        if display.isEmpty { return "''" }
        if display == "~" { return "~" }
        let startsWithTilde = display.hasPrefix("~/")
        let toCheck = startsWithTilde ? String(display.dropFirst(2)) : display
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=+,@")
        if toCheck.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return display
        }
        var result = startsWithTilde ? "~/" : ""
        for char in toCheck {
            if let scalar = char.unicodeScalars.first, safe.contains(scalar) {
                result.append(char)
            } else {
                result.append("\\")
                result.append(char)
            }
        }
        return result
    }
}
