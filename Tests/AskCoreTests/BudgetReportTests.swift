import AemiJSON
import AskCore
import Testing

/// `ask --budgets` is a contract with `Scripts/measure-budgets.py`, which reads exactly these four keys.
@Suite("The budget report is the one definition the measurement script reads")
struct BudgetReportTests {
    private struct Report: Decodable, Equatable {
        let coldStartMilliseconds: Double
        let idleMemoryMebibytes: Int
        let inputDelayMilliseconds: Double
        let actionToActionMilliseconds: Double
    }

    @Test func `the report carries the four budgets under the keys the script reads`() throws {
        let report = try AemiJSON.JSONDecoder().decode(Report.self, from: Budget.reportJSON())
        #expect(
            report
                == Report(
                    coldStartMilliseconds: Budget.coldStartMilliseconds,
                    idleMemoryMebibytes: Budget.idleMemoryMebibytes,
                    inputDelayMilliseconds: Budget.inputDelayMilliseconds,
                    actionToActionMilliseconds: Budget.actionToActionMilliseconds))
    }

    @Test func `the report is newline terminated for a line-reading consumer`() throws {
        #expect(try Budget.reportJSON().last == 0x0A)
    }
}
