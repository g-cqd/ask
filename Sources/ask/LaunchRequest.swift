internal import AskAI
internal import AskAgentCore
internal import AskCore
internal import AskTUI
internal import Foundation

/// What a launch takes from the command line, as plain values. The defaults are a bare `ask`: nothing given, the
/// interactive screen in a new session. ``Ask`` builds one from its parsed options; a bare launch builds the default
/// directly, so both run the one implementation below.
struct LaunchRequest {
    var budgets = false
    var prompt: String?
    var model: String?
    var provider: String?
    var thinking: String?
    var maxTurns: Int?
    var compactAt: Int?
    var noSandbox = false
    var network: String?
    var write: String?
    var read: String?
    var selfCheck = false
    var verbose = false
    var reloadedFrom: String?
    var reloadStarted: Int?
    var selectedProvider: String?
    var selectedModel: String?
    var continueLatest = false
    var resume: String?

    /// `--write` or `--read` as a setting.
    private static func scope(_ value: String?) -> PathSetting? {
        switch value {
            case nil: nil
            case "workspace": .workspace
            case "anywhere": .anywhere
            case let path?: .paths([path])
        }
    }

    private var session: SessionChoice {
        if let resume, !resume.isEmpty { return .named(resume) }
        return continueLatest ? .latest : .new
    }

    func run() async throws {
        if budgets {
            FileHandle.standardOutput.write(Data(try Budget.reportJSON()))
            return
        }
        var startupNotices: [String] = []
        let restored =
            selfCheck
            ? nil
            : session.open(
                in: SessionDirectory(
                    project: FileManager.default.currentDirectoryPath, environment: LaunchEnvironment.values),
                note: { startupNotices.append($0) })
        var source = ConfigurationSource(
            workingDirectory: FileManager.default.currentDirectoryPath,
            flags: .init(
                model: model, provider: provider, maxTurns: maxTurns, compactAt: compactAt,
                thinking: thinking.flatMap(ThinkingLevel.init(rawValue:)), noSandbox: noSandbox, verbose: verbose,
                network: network.flatMap(SandboxPolicy.Network.init(named:)), write: Self.scope(write),
                read: Self.scope(read),
                selected: selectedProvider.flatMap { provider in
                    selectedModel.map { ModelSelection(provider: provider, model: $0) }
                }))
        source = source.resuming(restored)
        let settings: RunSettings
        do { settings = try await source.load(allowNetwork: !selfCheck) } catch {
            fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error))
        }
        if selfCheck {
            checkSelf(settings)
            return
        }
        let reloaded = reloadedFrom.map { ReloadNotice(from: $0, startedMilliseconds: reloadStarted ?? 0) }
        if let prompt {
            await runPrompt(
                prompt, source: source, settings: settings, resumed: restored, startupNotices: startupNotices)
            return
        }
        await runInteractive(
            source: source, settings: settings, resumed: restored, startupNotices: startupNotices, reloaded: reloaded,
            pickSession: resume == "")
    }
}
