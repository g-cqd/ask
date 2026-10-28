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

    /// Formats an OSC 8 terminal hyperlink for a file path, with an absolute `file://` URI.
    public static func link(to path: String, display: String? = nil) -> String {
        let label = display ?? tilde(path)
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
