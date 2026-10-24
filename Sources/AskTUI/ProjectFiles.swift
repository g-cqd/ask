/// The files of the project the `@` picker offers, listed by the composition root (roadmap 0048).
///
/// The paths are relative to the working directory, in the order they were listed. Alongside them the type keeps every path lowercased and
/// laid end to end in one buffer, with where each starts and where its last component starts, so a keystroke searches one contiguous array
/// and not twenty thousand strings. It is built where the listing is made, off the input path.
public struct ProjectFiles: Sendable, Equatable {
    /// Relative paths, as listed.
    public let paths: [String]
    /// How many files the sandbox would not let ask read, which are not in ``paths``.
    public let hidden: Int
    /// Whether the listing stopped at its limit, so ``paths`` is not the whole project.
    public let truncated: Bool
    /// Every path lowercased, end to end.
    let lowered: ContiguousArray<UInt8>
    /// Where path `i` starts in ``lowered``; one more entry marks the end of the last.
    let starts: [Int]
    /// Where the last component of path `i` starts in ``lowered``.
    let baseStarts: [Int]

    /// A listing of `paths`.
    public init(paths: [String], hidden: Int = 0, truncated: Bool = false) {
        self.paths = paths
        self.hidden = hidden
        self.truncated = truncated
        var lowered = ContiguousArray<UInt8>()
        var starts: [Int] = []
        var baseStarts: [Int] = []
        starts.reserveCapacity(paths.count + 1)
        baseStarts.reserveCapacity(paths.count)
        for path in paths {
            starts.append(lowered.count)
            let bytes = Array(path.lowercased().utf8)
            lowered.append(contentsOf: bytes)
            baseStarts.append(lowered.count - bytes.reversed().prefix { $0 != UInt8(ascii: "/") }.count)
        }
        starts.append(lowered.count)
        self.lowered = lowered
        self.starts = starts
        self.baseStarts = baseStarts
    }

    /// No files: nothing listed, nothing hidden.
    public init() { self.init(paths: []) }
}
