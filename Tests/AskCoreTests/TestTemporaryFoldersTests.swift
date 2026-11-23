internal import Foundation
internal import Testing

@testable import AskCore

/// A test that makes a folder of its own in the temporary directory removes it (t126): a full run left 612 behind, and the folder
/// held 48,566. A test file that names an `ask-` folder there and writes into it also calls `removeItem` or `cleanup()`. The files
/// that did not when the rule came are listed in ``leaking``, a ratchet: an entry leaves when its file is fixed, none is added.
@Suite("A test removes the temporary folder it makes")
struct TestTemporaryFoldersTests {
    /// Calls that put something on disk.
    static let writes = [
        "createDirectory", ".write(to:", "createFile", "mkdir(", ".copyItem", "SessionFile.create", ".write(toFile"
    ]

    /// Whether `text`, a test file, makes an `ask-` folder in the temporary directory and leaves it.
    static func leaves(_ text: String) -> Bool {
        let names = text.ranges(of: "\"ask-")
            .contains { name in
                let before = text[
                    text.index(
                        name.lowerBound,
                        offsetBy: -min(80, text.distance(from: text.startIndex, to: name.lowerBound))
                    ) ..< name.lowerBound
                ]
                return before.contains("temporaryDirectory") || before.contains("NSTemporaryDirectory()")
            }
        return names && writes.contains(where: text.contains) && !text.contains("removeItem")
            && !text.contains(".cleanup()")
    }

    /// The test files, relative to `Tests`, that left their folders when the rule came.
    static let leaking: Set<String> = [
        "AskAITests/AgyModelCatalogTests.swift",
        "AskAITests/AgyVersionsTests.swift",
        "AskAITests/AtomicFileDurabilityTests.swift",
        "AskAITests/CodexAccessTests.swift",
        "AskAITests/ConnectionSharedAccountTests.swift",
        "AskAITests/CredentialAccountNameTests.swift",
        "AskAITests/CredentialFileAccountsTests.swift",
        "AskAITests/CredentialFileAgyTests.swift",
        "AskAITests/CredentialFileProvidersTests.swift",
        "AskAITests/CredentialFileTests.swift",
        "AskAITests/CredentialFileTransactionTests.swift",
        "AskAITests/ModelAccountMemoryTests.swift",
        "AskAITests/ProviderFileTests.swift",
        "AskAgentCoreTests/AgentHookApprovalTests.swift",
        "AskAgentCoreTests/AgentHookPointsTests.swift",
        "AskAgentCoreTests/AgentHookPromptTests.swift",
        "AskAgentCoreTests/AgentHookRunStopTests.swift",
        "AskAgentCoreTests/AgentHookTests.swift",
        "AskAgentCoreTests/AgentLoopAsideTests.swift",
        "AskAgentCoreTests/AgentLoopHandoverTests.swift",
        "AskAgentCoreTests/AgentLoopNetworkWaitTests.swift",
        "AskAgentCoreTests/AgentLoopReconnectTests.swift",
        "AskAgentCoreTests/AgentLoopRetryTests.swift",
        "AskAgentCoreTests/AgentLoopTests.swift",
        "AskAgentCoreTests/ConfigEditorKeepsCommentsTests.swift",
        "AskAgentCoreTests/ConfigEditorModelTests.swift",
        "AskAgentCoreTests/HookRequestRewriteTests.swift",
        "AskAgentCoreTests/Ideas/IdeaBoardTests.swift",
        "AskAgentCoreTests/Lists/ChangeRecordTests.swift",
        "AskAgentCoreTests/NestedToolCallsTests.swift",
        "AskAgentCoreTests/NoticingProviderTests.swift",
        "AskAgentCoreTests/ProjectInstructionsTests.swift",
        "AskAgentCoreTests/ProjectTrustDurabilityTests.swift",
        "AskAgentCoreTests/RepositoryFactsTests.swift",
        "AskAgentCoreTests/SandboxAskablePathsTests.swift",
        "AskAgentCoreTests/SandboxConfigurationTests.swift",
        "AskAgentCoreTests/SandboxPolicyTests.swift",
        "AskAgentCoreTests/SandboxStandardTests.swift",
        "AskAgentCoreTests/SessionDirectoryPermissionsTests.swift",
        "AskAgentCoreTests/SessionFileFailureTests.swift",
        "AskAgentCoreTests/SessionFileTests.swift",
        "AskAgentCoreTests/SessionForkTests.swift",
        "AskAgentCoreTests/SessionInFileTests.swift",
        "AskAgentCoreTests/SessionLockTests.swift",
        "AskAgentCoreTests/SessionLookupTests.swift",
        "AskAgentCoreTests/SessionRecorderCheckoutTests.swift",
        "AskAgentCoreTests/SessionRepairNoticeTests.swift",
        "AskAgentCoreTests/SessionSandboxRecordTests.swift",
        "AskAgentCoreTests/SessionSearchTests.swift",
        "AskAgentCoreTests/SteeringTests.swift",
        "AskAgentCoreTests/Storage/EncryptPicturesTests.swift",
        "AskAgentCoreTests/Storage/EncryptedImageTests.swift",
        "AskAgentCoreTests/Storage/SessionFileFormatTests.swift",
        "AskAgentCoreTests/Storage/SessionSummaryFramedTests.swift",
        "AskAgentCoreTests/Storage/SessionVaultTests.swift",
        "AskAgentCoreTests/Tasks/TaskBoardTests.swift",
        "AskAgentCoreTests/Tasks/TaskLogTests.swift",
        "AskAgentCoreTests/ToolProgressTests.swift",
        "AskToolsTests/BashToolTests.swift",
        "AskToolsTests/BinaryIdentityTests.swift",
        "AskToolsTests/BinaryWatcherTests.swift",
        "AskToolsTests/BuildSignatureTests.swift",
        "AskToolsTests/CommandEnvironmentJobTests.swift",
        "AskToolsTests/FileToolsTests.swift",
        "AskToolsTests/IdeasToolTests.swift",
        "AskToolsTests/ImageReadTests.swift",
        "AskToolsTests/JobOutputFileTests.swift",
        "AskToolsTests/JobToolsTests.swift",
        "AskToolsTests/MediaReadTests.swift",
        "AskToolsTests/PDFTextTests.swift",
        "AskToolsTests/ShellReadinessTests.swift",
        "AskToolsTests/TasksToolTests.swift",
        "AskToolsTests/VideoReadTests.swift"
    ]

    @Test func `the rule finds a folder made and left, and accepts one removed or only named`() {
        let made = "let root = FileManager.default.temporaryDirectory.appending(path: \"ask-x-\\(id)\")\n"
        let writes = "try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)\n"
        #expect(Self.leaves(made + writes))
        #expect(!Self.leaves(made + writes + "defer { try? FileManager.default.removeItem(at: root) }\n"))
        #expect(!Self.leaves(made + writes + "dir.cleanup()\n"))
        #expect(!Self.leaves(made), "a path only named is not a folder made")
        #expect(!Self.leaves("let other = \"ask-x\"\n" + writes), "an `ask-` name elsewhere")
    }

    @Test func `no test leaves a temporary folder it made, beyond those listed, and none listed is fixed`() throws {
        let root = SourceStandards.repositoryRoot.appending(path: "Tests")
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        var found: Set<String> = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if Self.leaves(text) { found.insert(file.path.replacingOccurrences(of: root.path + "/", with: "")) }
        }
        #expect(
            found.subtracting(Self.leaking).isEmpty,
            "remove the folder the test makes: \(found.subtracting(Self.leaking).sorted())"
        )
        #expect(
            Self.leaking.subtracting(found).isEmpty,
            "fixed, so take it off the list: \(Self.leaking.subtracting(found).sorted())"
        )
    }
}
