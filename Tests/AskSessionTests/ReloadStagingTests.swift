internal import AskTools
internal import Darwin
internal import Foundation
internal import Testing

@testable import AskSession

/// `ReloadStaging` (security audit 2026-11-22, HIGH-10): `/reload` copies the candidate into `<config>/reload/ask-staged-<uuid>` with
/// `0500` permissions (`O_NOFOLLOW`), so mutating or replacing the external path after staging cannot change what `BuildSignature`,
/// `SelfCheck` and `execve` run; symlinks are refused, and old staged copies are swept while keeping the running image.
@Suite("ReloadStaging isolates /reload from post-check binary swaps")
struct ReloadStagingTests {
    @Test
    func `staging creates an immutable 0500 copy immune to external swaps, refuses symlinks, and sweeps old copies`()
        throws
    {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ask-reload-stage-\(UUID().uuidString)", isDirectory: true)
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binURL = root.appendingPathComponent("ask-candidate")
        try Data("#!/bin/sh\necho v1\n".utf8).write(to: binURL)
        _ = chmod(binURL.path, 0o755)
        let originalIdentity = try #require(BinaryIdentity(path: binURL.path))

        let staged1 = try ReloadStaging.stage(binURL.path, configDirectory: configDir.path)
        let stagedAttrs = try FileManager.default.attributesOfItem(atPath: staged1)
        #expect((stagedAttrs[.posixPermissions] as? Int) == 0o500)
        let folderAttrs = try FileManager.default.attributesOfItem(atPath: configDir.path + "/reload")
        #expect((folderAttrs[.posixPermissions] as? Int) == 0o700)

        // Mutating or replacing the source path after staging leaves the staged copy untouched.
        try Data("#!/bin/sh\necho attacker-swapped\n".utf8).write(to: binURL, options: .atomic)
        #expect(try String(contentsOfFile: staged1, encoding: .utf8) == "#!/bin/sh\necho v1\n")

        // Preserved mtime lets BinaryIdentity.watching match the build's timestamp and size.
        let stagedIdentity = try #require(BinaryIdentity(path: staged1))
        #expect(stagedIdentity.size == originalIdentity.size)
        #expect(stagedIdentity.summary == originalIdentity.summary)

        // Symlink candidates are refused by O_NOFOLLOW.
        let linkURL = root.appendingPathComponent("ask-symlink")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: binURL)
        #expect(throws: ReloadStaging.Failure.self) {
            _ = try ReloadStaging.stage(linkURL.path, configDirectory: configDir.path)
        }

        // Sweep deletes previous ask-staged-* copies while keeping the running one.
        let staged2 = try ReloadStaging.stage(binURL.path, configDirectory: configDir.path)
        ReloadStaging.sweepPrevious(configDirectory: configDir.path, keeping: staged2)
        #expect(!FileManager.default.fileExists(atPath: staged1))
        #expect(FileManager.default.fileExists(atPath: staged2))
    }
}
