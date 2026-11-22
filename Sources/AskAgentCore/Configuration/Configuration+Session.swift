extension Configuration {
    /// `self` narrowed by the strict sandbox a resumed session recorded, except for what a flag set: a flag is the
    /// user widening on purpose. The record only ever narrows; the source changes only when it did.
    public func applying(
        session record: SandboxSection,
        flaggedNetwork: Bool,
        flaggedWrite: Bool,
        flaggedRead: Bool
    ) -> Configuration {
        // `anywhere` narrows nothing, and with writing kept to the workspace by default it would widen: a record keeps only the scopes
        // that narrow, so a session file, which may come from anywhere, can never open the sandbox.
        let narrowing = { (scopes: [PathSetting]) in scopes.filter { $0 != .anywhere } }
        let narrowed = sandbox.value.layered(
            with: SandboxSection(
                write: flaggedWrite ? [] : narrowing(record.write),
                read: flaggedRead ? [] : narrowing(record.read),
                network: flaggedNetwork ? nil : record.network
            )
        )
        guard narrowed != sandbox.value else { return self }
        var next = self
        next.sandbox = Setting(value: narrowed, source: .session)
        return next
    }
}
