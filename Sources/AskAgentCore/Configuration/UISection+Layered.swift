extension UISection {
    /// `self` with every key `section` sets replaced.
    public func layered(with section: UISection) -> UISection {
        var merged = UISection(
            // @dl:accept -- each configuration field independently takes its later non-nil value
            mouse: section.mouse ?? mouse,
            copyOnSelect: section.copyOnSelect ?? copyOnSelect,
            foldTools: section.foldTools ?? foldTools,
            foldThinking: section.foldThinking ?? foldThinking,
            scrollLines: section.scrollLines ?? scrollLines,
            promptRows: section.promptRows ?? promptRows,
            foldCode: section.foldCode ?? foldCode,
            codeFoldLines: section.codeFoldLines ?? codeFoldLines,
            outputFoldLines: section.outputFoldLines ?? outputFoldLines,
            outputFoldBytes: section.outputFoldBytes ?? outputFoldBytes,
            sidebarOpen: section.sidebarOpen ?? sidebarOpen,
            sidebarJobsInTree: section.sidebarJobsInTree ?? sidebarJobsInTree,
            prompt: section.prompt ?? prompt,
            tint: section.tint ?? tint,
            // @dl:accept -- each section layers its keys the same way; the key lists are the data
            separator: section.separator ?? separator,
            padding: section.padding ?? padding,
            markdown: section.markdown ?? markdown,
            highlight: section.highlight ?? highlight,
            shimmer: section.shimmer ?? shimmer,
            hover: section.hover ?? hover,
            localizedDurations: section.localizedDurations ?? localizedDurations,
            spinner: section.spinner ?? spinner,
            jobAutoReturnWhenFocused: section.jobAutoReturnWhenFocused ?? jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: section.abortTurnRequiresConfirmation ?? abortTurnRequiresConfirmation,
            interruptKeys: section.interruptKeys ?? interruptKeys,
            escapeInterruptRequiresConfirmation: section.escapeInterruptRequiresConfirmation
                ?? escapeInterruptRequiresConfirmation,
            interruptSendsQueued: section.interruptSendsQueued ?? interruptSendsQueued,
            onlyUsefulModels: section.onlyUsefulModels ?? onlyUsefulModels,
            appearance: section.appearance ?? appearance,
            // @dl:accept -- every section layers its keys this way; the key lists are the data
            timeout: section.timeout ?? timeout,
            timeoutLabel: section.timeoutLabel ?? timeoutLabel,
            sessionColor: section.sessionColor ?? sessionColor
        )
        merged.sidebarLayout = section.sidebarLayout ?? sidebarLayout
        merged.dim = section.dim ?? dim
        merged.sessionTint = section.sessionTint ?? sessionTint
        merged.paths = section.paths ?? paths
        merged.pathAncestors = section.pathAncestors ?? pathAncestors
        merged.notify = section.notify ?? notify
        merged.statusPath = section.statusPath ?? statusPath
        merged.statusPathSide = section.statusPathSide ?? statusPathSide
        merged.historyLimit = section.historyLimit ?? historyLimit
        return merged
    }
}
