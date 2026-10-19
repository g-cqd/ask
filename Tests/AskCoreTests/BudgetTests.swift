internal import AskCore
import Foundation
import Testing

/// A budget nothing checks is a wish.
///
/// The numbers in `Budget` were measured once and could silently stop being true. These tests check
/// the arithmetic that decides pass or fail — not the performance of the binary, which belongs to
/// `Scripts/measure-budgets.py` against real hardware — so that a mistake in the guard itself cannot
/// quietly let everything through.
///
/// The guard was probed before being trusted: see `the boundary is inclusive`.
@Suite("Budgets decide pass and fail correctly")
struct BudgetTests {
    @Test func `a measurement well inside every budget passes`() {
        #expect(
            Budget.isWithinBudget(
                coldStart: 11.06, idleMemoryMebibytes: 5.7, inputDelay: 0.12, action: 0.05))
    }

    @Test func `the measured baseline itself passes`() {
        // The exact numbers measured on the development machine. A budget the current code fails is
        // a budget that will be raised on the first bad day rather than defended.
        #expect(
            Budget.isWithinBudget(
                coldStart: 11.06, idleMemoryMebibytes: 5712.0 / 1024, inputDelay: 0.12, action: 0.05))
    }

    @Test func `a cold start over budget fails`() {
        #expect(
            !Budget.isWithinBudget(
                coldStart: Budget.coldStartMilliseconds + 1, idleMemoryMebibytes: 5.7,
                inputDelay: 0.12, action: 0.05),
            "a cold start over budget passed")
    }

    @Test func `idle memory over budget fails`() {
        #expect(
            !Budget.isWithinBudget(
                coldStart: 5, idleMemoryMebibytes: Double(Budget.idleMemoryMebibytes) + 0.5,
                inputDelay: 0.12, action: 0.05),
            "idle memory over budget passed")
    }

    @Test func `input delay over budget fails`() {
        #expect(
            !Budget.isWithinBudget(
                coldStart: 5, idleMemoryMebibytes: 5.7,
                inputDelay: Budget.inputDelayMilliseconds + 0.1, action: 0.05),
            "input delay over budget passed")
    }

    @Test func `action delay over budget fails`() {
        #expect(
            !Budget.isWithinBudget(
                coldStart: 5, idleMemoryMebibytes: 5.7, inputDelay: 0.12,
                action: Budget.actionToActionMilliseconds + 0.1),
            "action delay over budget passed")
    }

    @Test func `the boundary is inclusive`() {
        // A budget that fails on the exact number means a measurement landing precisely on the limit
        // is reported as a regression with nothing actually having changed.
        #expect(
            Budget.isWithinBudget(
                coldStart: Budget.coldStartMilliseconds,
                idleMemoryMebibytes: Double(Budget.idleMemoryMebibytes),
                inputDelay: Budget.inputDelayMilliseconds,
                action: Budget.actionToActionMilliseconds),
            "a measurement exactly on every limit was rejected")
    }

    @Test func `every budget is positive and finite`() {
        // A zero or negative budget fails everything, including the code that ships today, and the
        // failure looks like a performance regression rather than a typo.
        let budgets = [
            Budget.coldStartMilliseconds, Double(Budget.idleMemoryMebibytes),
            Budget.inputDelayMilliseconds, Budget.actionToActionMilliseconds
        ]
        for budget in budgets {
            #expect(budget > 0, "a budget is not positive: \(budget)")
            #expect(budget.isFinite, "a budget is not finite: \(budget)")
        }
    }

    @Test func `the idle memory budget is the 24 MiB the owner chose, so changing it is a deliberate act`() {
        // ADR-0038. The earlier 8 MiB had been exceeded since before the agent loop landed; the measured median is
        // about 9 MiB. Moving this number again means editing this test and writing down why.
        #expect(Budget.idleMemoryMebibytes == 24)
    }

    @Test func `every budget sits above what was measured`() {
        // Measured: 11.06 ms cold start, 5.58 MiB idle, 0.12 ms input, 0.05 ms action. A budget at or
        // below the measurement would leave no room for ordinary variance.
        #expect(Budget.coldStartMilliseconds > 11.06)
        #expect(Double(Budget.idleMemoryMebibytes) > 5712.0 / 1024)
        #expect(Budget.inputDelayMilliseconds > 0.12)
        #expect(Budget.actionToActionMilliseconds > 0.05)
    }
}
