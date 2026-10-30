internal import AskAgentCore
internal import AskTUI

extension RunSettings {
    /// Every `ui` and `skills` key with the value in force and where it came from, then the MCP servers: what `ask config` and `/config`
    /// show after the top-level settings (roadmap 0103). A key no layer set shows the default the program uses.
    var sectionRows: [String] {
        let c = configuration
        let ui = effectiveUI
        let skills = SkillsSection(
            enabled: c.skills.value.enabled ?? true,
            maxAdvertised: c.skills.value.maxAdvertised ?? SkillsSection.defaultMaxAdvertised,
            sources: c.skills.value.sources)
        func pad(_ text: String, _ width: Int) -> String {
            text + String(repeating: " ", count: max(1, width - text.count))
        }
        func rows(_ section: String, _ keys: [String], _ value: (String) -> String) -> [String] {
            let width = (keys.map(\.count).max() ?? 0) + 2
            return keys.enumerated()
                .map { index, key in
                    let head = pad(index == 0 ? section : "", 10)
                    let name = pad(key, width)
                    return head + name + value(key) + "  [\(c.source(ofKey: section + "." + key))]"
                }
        }
        let mcp =
            pad("mcp", 10) + c.mcp.value.description
            + (c.mcp.value.servers.isEmpty ? "" : "  [\(c.mcp.source)]")
        return rows("ui", UISection.keys) { ui.value(forKey: $0) ?? "" }
            + rows("skills", SkillsSection.keys) { skills.value(forKey: $0) ?? "every harness" } + [mcp]
    }

    /// The `ui` section as the screen uses it: each key a file set, and the screen's own default for the rest.
    var effectiveUI: UISection {
        let options = screenOptions
        return UISection(
            mouse: options.mouse, copyOnSelect: options.copyOnSelect, foldTools: options.foldTools,
            foldThinking: options.foldThinking, scrollLines: options.scrollLines, promptRows: options.promptRows,
            foldCode: options.foldCode, codeFoldLines: options.codeFoldLines, sidebarOpen: options.sidebar,
            prompt: options.prompt, tint: options.tint, separator: options.separator, padding: options.padding,
            markdown: options.markdown,
            localizedDurations: options.localizedDurations,
            spinner: SpinnerPreference(rawValue: options.spinner.rawValue),
            jobAutoReturnWhenFocused: options.jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: options.abortTurnRequiresConfirmation,
            interruptKeys: InterruptKeysPreference(rawValue: options.interruptKeys.rawValue),
            escapeInterruptRequiresConfirmation: options.escapeInterruptRequiresConfirmation,
            interruptSendsQueued: QueuedAfterInterruptPreference(rawValue: options.interruptSendsQueued.rawValue),
            onlyUsefulModels: configuration.ui.value.onlyUsefulModels ?? true,
            appearance: AppearancePreference(rawValue: options.appearance.rawValue),
            timeout: TimeoutPreference(rawValue: options.timeoutDisplay.rawValue), timeoutLabel: options.timeoutLabel,
            sessionColor: configuration.ui.value.sessionColor ?? .off)
    }

    /// `compactAt` in words: a share of the window, a number of tokens, or only when the window is full.
    static func describe(_ threshold: CompactionThreshold) -> String {
        switch threshold {
            case .share(let percent): "\(percent)% of the model's window"
            case .tokens(0): "0 (only when the window is full)"
            case .tokens(let count): "\(count) tokens"
        }
    }
}
