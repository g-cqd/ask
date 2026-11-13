extension Ask {
    /// What this command line asks for, as plain values (see ``LaunchRequest``).
    var request: LaunchRequest {
        LaunchRequest(
            budgets: budgets,
            // @dl:accept -- every launch option passed through as a value, one per line: the request's shape, not repeated logic
            prompt: prompt,
            json: json,
            model: model,
            provider: provider,
            thinking: thinking,
            maxTurns: maxTurns,
            compactAt: compactAt,
            noSandbox: noSandbox,
            yes: yes,
            yolo: yolo,
            allow: allow,
            ask: ask,
            askAlways: askAlways,
            network: network,
            write: write,
            read: read,
            selfCheck: selfCheck,
            verbose: verbose,
            reloadedFrom: reloadedFrom,
            reloadStarted: reloadStarted,
            reloadGrants: reloadGrants,
            focusThread: focusThread,
            selectedProvider: selectedProvider,
            selectedModel: selectedModel,
            continueLatest: continueLatest,
            resume: resume
        )
    }
}
