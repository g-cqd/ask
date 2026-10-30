extension SandboxPolicy {
    /// What a run that keeps writing to its workspace may still write in `home` (owner, 2026-10-29): the caches builds write there,
    /// SwiftPM's and Xcode's, and `~/Library/Caches`, where a `.build` linked out of the project lands. Not toolchains, not `~/.cache`
    /// (tools keep runnable environments there, such as pre-commit's), not anything that runs later.
    public static func developerWrites(home: String) -> [String] {
        ["Library/Caches", "Library/Developer/Xcode/DerivedData", "Library/org.swift.swiftpm", ".swiftpm"]
            .map { home + "/" + $0 }
    }
}
