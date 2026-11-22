internal import AskAgentCore
internal import AskCore
internal import AskTUI

extension RunSettings {
    /// Every `ui`, `skills` and `hooks` key with the value in force and where it came from, then the MCP servers: what `ask config` and `/config`
    /// show after the top-level settings (roadmap 0103). A key no layer set shows the default the program uses.
    var sectionRows: [String] {
        let c = configuration
        let ui = effectiveUI
        let skills = SkillsSection(
            enabled: c.skills.value.enabled ?? true,
            maxAdvertised: c.skills.value.maxAdvertised ?? SkillsSection.defaultMaxAdvertised,
            sources: c.skills.value.sources
        )
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
        // The section's source is the last file that set any of its keys.
        let hookValues = c.hooks.value
        let hooks = HooksSection.keys.enumerated()
            .map { index, key in
                let shown =
                    switch key {
                        case "maxContinues": String(hookValues.continues)
                        case "checkTimeout": "\(hookValues.checkSeconds) s"
                        default: hookValues.value(forKey: key) ?? "none"
                    }
                return pad(index == 0 ? "hooks" : "", 10) + pad(key, 14) + shown + "  [\(c.hooks.source)]"
            }
        let mcp =
            pad("mcp", 10) + c.mcp.value.description
            + (c.mcp.value.servers.isEmpty ? "" : "  [\(c.mcp.source)]")
        return rows("ui", UISection.keys) { ui.value(forKey: $0) ?? "" }
            + rows("skills", SkillsSection.keys) { skills.value(forKey: $0) ?? "every harness" } + hooks + [mcp]
    }

    /// The `ui` section as the screen uses it: each key a file set, and the screen's own default for the rest.
    var effectiveUI: UISection {
        let options = screenOptions
        var ui = UISection.empty
        // @dl:accept -- one assignment per key, from what the screen uses: the keys are the data
        ui.mouse = options.mouse
        ui.copyOnSelect = options.copyOnSelect
        ui.foldTools = options.foldTools
        ui.foldThinking = options.foldThinking
        ui.scrollLines = options.scrollLines
        ui.promptRows = options.promptRows
        ui.foldCode = options.foldCode
        ui.codeFoldLines = options.codeFoldLines
        ui.sidebarOpen = options.sidebar
        ui.prompt = options.prompt
        ui.tint = options.tint
        ui.separator = options.separator
        ui.padding = options.padding
        ui.markdown = options.markdown
        ui.localizedDurations = options.localizedDurations
        ui.spinner = options.spinner
        ui.jobAutoReturnWhenFocused = options.jobAutoReturnWhenFocused
        ui.abortTurnRequiresConfirmation = options.abortTurnRequiresConfirmation
        ui.interruptKeys = options.interruptKeys
        ui.escapeInterruptRequiresConfirmation = options.escapeInterruptRequiresConfirmation
        ui.interruptSendsQueued = options.interruptSendsQueued
        ui.onlyUsefulModels = configuration.ui.value.onlyUsefulModels ?? true
        ui.appearance = options.appearance
        ui.timeout = options.timeoutDisplay
        ui.timeoutLabel = options.timeoutLabel
        ui.sessionColor = configuration.ui.value.sessionColor ?? .off
        ui.outputFoldLines = options.outputFoldLines
        ui.outputFoldBytes = options.outputFoldBytes
        ui.notify = options.notify
        ui.statusPath = options.statusPath
        ui.statusPathSide = options.statusPathSide
        ui.historyLimit = options.historyLimit ?? UISection.noHistoryLimit
        return ui
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
