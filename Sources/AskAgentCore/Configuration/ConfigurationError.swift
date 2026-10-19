/// Why a configuration file was refused. A refused file changes nothing: the previous configuration stays.
public enum ConfigurationError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The file could not be read.
    case unreadable(path: String, errno: Int32)
    /// Not JSON or JSON5, or a value of the wrong type; `line` and `column` are 1-based when known.
    case invalid(path: String, line: Int?, column: Int?, reason: String)
    /// A key ask does not know, which is usually a typo.
    case unknownKey(path: String, key: String, known: [String])
    /// A value of the right type outside what the key allows.
    case outOfRange(path: String, key: String, reason: String)

    public var description: String {
        switch self {
            case .unreadable(let path, let errno): "\(path): cannot be read (errno \(errno))"
            case .invalid(let path, let line, let column, let reason):
                "\(path)\(line.map { ":\($0)" } ?? "")\(column.map { ":\($0)" } ?? ""): \(reason)"
            case .unknownKey(let path, let key, let known):
                "\(path): unknown key \"\(key)\"; ask knows " + known.map { "\"\($0)\"" }.joined(separator: ", ")
            case .outOfRange(let path, let key, let reason): "\(path): \"\(key)\" \(reason)"
        }
    }
}
