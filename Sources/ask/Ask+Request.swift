internal import AskSession

extension Ask {
    /// What this command line asks for, as plain values (see ``LaunchRequest``).
    var request: LaunchRequest {
        var request = LaunchRequest()
        // @dl:accept -- every launch option passed through as a value, one per line: the request's shape, not repeated logic
        request.budgets = budgets
        request.prompt = prompt
        request.json = json
        request.model = model
        request.provider = provider
        request.thinking = thinking
        request.maxTurns = maxTurns
        request.compactAt = compactAt
        request.noSandbox = noSandbox
        request.yes = yes
        request.yolo = yolo
        request.allow = allow
        request.ask = ask
        request.askAlways = askAlways
        request.network = network
        request.write = write
        request.read = read
        request.selfCheck = selfCheck
        request.verbose = verbose
        request.reloadedFrom = reloadedFrom
        request.reloadStarted = reloadStarted
        request.reloadGrants = reloadGrants
        request.focusThread = focusThread
        request.selectedProvider = selectedProvider
        request.selectedModel = selectedModel
        request.continueLatest = continueLatest
        request.resume = resume
        return request
    }
}
