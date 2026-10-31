extension ConfigurationFile {
    /// Whether the file sets the key `name`.
    public func sets(_ name: String) -> Bool {
        switch name {
            case "model": model != nil
            case "provider": provider != nil
            case "thinking": thinking != nil
            case "maxTurns": maxTurns != nil
            case "compactAt": compactAt != nil
            case "keepAwake": keepAwake != nil
            case "keepDisplayAwake": keepDisplayAwake != nil
            case "credentials": credentials != nil
            case "approvals": approvals != nil
            case "modelScopes": modelScopes != nil
            case "sandbox": sandbox != nil
            case "ui": ui != nil
            case "skills": skills != nil
            case "mcp": mcp != nil
            case "environment": environment != nil
            default: false
        }
    }
}
