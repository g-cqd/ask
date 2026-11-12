extension ConfigurationFile {
    /// Whether the file sets the key `name`.
    public func sets(_ name: String) -> Bool {
        switch name {
            // @dl:accept -- one row per key, each naming its own field: the table is the data
            case "model": model != nil
            case "provider": provider != nil
            case "thinking": thinking != nil
            case "maxTurns": maxTurns != nil
            case "compactAt": compactAt != nil
            case "keepAwake": keepAwake != nil
            case "keepDisplayAwake": keepDisplayAwake != nil
            case "sessionEncryption", "sessionCompression", "sessionPassword", "taskScope": setsSessionKey(name)
            // @dl:accept -- one row per key, each naming its own field: the table is the data
            case "credentials": credentials != nil
            case "approvals": approvals != nil
            case "modelScopes": modelScopes != nil
            case "hooks": hooks != nil
            case "threads": threads != nil
            case "agents": agents != nil
            case "sandbox": sandbox != nil
            case "ui": ui != nil
            case "skills": skills != nil
            case "mcp": mcp != nil
            case "presets": presets != nil
            case "environment": environment != nil
            case "jobs": jobs != nil
            default: false
        }
    }
}
