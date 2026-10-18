internal import AemiJSON

extension Budget {
    /// The four budgets as one newline-terminated JSON object, for `ask --budgets`.
    ///
    /// `Scripts/measure-budgets.py` reads its limits from this output, so the numbers have one definition
    /// and no copy in a script that can drift.
    /// - Returns: the encoded report.
    /// - Throws: the encoder's error if encoding fails.
    public static func reportJSON() throws -> [UInt8] {
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        var bytes = try encoder.encodeToBytes(Report())
        bytes.append(0x0A)
        return bytes
    }

    private struct Report: Encodable {
        let coldStartMilliseconds = Budget.coldStartMilliseconds
        let idleMemoryMebibytes = Budget.idleMemoryMebibytes
        let inputDelayMilliseconds = Budget.inputDelayMilliseconds
        let actionToActionMilliseconds = Budget.actionToActionMilliseconds
    }
}
