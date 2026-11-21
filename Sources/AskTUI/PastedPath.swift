internal import Foundation

/// A pasted or dropped path that names a picture (roadmap 0224; the owner, 2026-11-12: attached, any other text stays text). A
/// terminal turns a file dropped on its window into its path: quoted, or with its spaces escaped, and often a blank around it.
enum PastedPath {
    /// The kinds of picture a path may name, by its extension; ask makes the others a PNG or JPEG before sending (roadmap 0084).
    static let extensions = Set(
        "png jpg jpeg gif webp heic heif avif tif tiff bmp".split(separator: " ").map(String.init)
    )

    /// The file `text` names, when it is one path, to a file that exists, named as a picture; nil for anything else.
    static func picture(_ text: String) -> String? {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.contains("\n") else { return nil }
        for quote in ["'", "\""] where path.count > 1 && path.hasPrefix(quote) && path.hasSuffix(quote) {
            path = String(path.dropFirst().dropLast())
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        if path.hasPrefix("~/") { path = NSHomeDirectory() + path.dropFirst() }
        guard path.hasPrefix("/"), extensions.contains((path as NSString).pathExtension.lowercased()) else {
            return nil
        }
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue else {
            return nil
        }
        return path
    }

    /// `paths` as a shell reads them, separated by a blank: each as it is when it holds only letters, digits and `/ . _ - + , : @ %`,
    /// else in single quotes. Nil when there is none, or when one holds a control character, which is never typed into a draft.
    static func typed(_ paths: [String]) -> String? {
        guard !paths.isEmpty, paths.allSatisfy(isTypeable) else { return nil }
        return paths.map(quoted).joined(separator: " ")
    }

    /// No control character (C0, DEL, C1) and no line or paragraph separator.
    private static func isTypeable(_ path: String) -> Bool {
        path.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && !(0x7F ... 0x9F).contains(scalar.value) && scalar.value != 0x2028
                && scalar.value != 0x2029
        }
    }

    private static func quoted(_ path: String) -> String {
        let plain = path.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar)
                    || "/._-+,:@%".unicodeScalars.contains(scalar))
        }
        return plain ? path : "'" + path.replacing("'", with: #"'\''"#) + "'"
    }
}
