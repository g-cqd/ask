internal import Darwin
internal import Testing

@testable import AskCore

/// Blanking variables in the process's own environment, so another process cannot read them from it (ADR-0112).
/// The kernel-visible copy is covered by `Scripts/probe-bash-parent-environment.py`; these tests cover which entries change.
@Suite("Concealed variables are blanked in place, and nothing else changes", .serialized)
struct ProcessEnvironmentTests {
    private func set(_ name: String, _ value: String) { setenv(name, value, 1) }
    private func get(_ name: String) -> String? { getenv(name).map { String(cString: $0) } }

    @Test func `a chosen variable is blanked and its neighbours are not`() {
        set("ASK_CONCEAL_A", "secret-a")
        set("ASK_CONCEAL_B", "keep-b")
        ProcessEnvironment.conceal { $0 == "ASK_CONCEAL_A" }
        #expect(get("ASK_CONCEAL_A") == "")
        #expect(get("ASK_CONCEAL_B") == "keep-b")
    }

    @Test func `the predicate sees the name only, never the value`() {
        set("ASK_CONCEAL_C", "value-with=equals")
        var seen: [String] = []
        ProcessEnvironment.conceal {
            if $0.hasPrefix("ASK_CONCEAL_") { seen.append($0) }
            return false
        }
        #expect(seen.contains("ASK_CONCEAL_C"))
        #expect(!seen.contains { $0.contains("=") || $0.contains("value-with") }, "a name never carries its value")
        #expect(get("ASK_CONCEAL_C") == "value-with=equals")
    }

    @Test func `a value that contains an equals sign is blanked whole`() {
        set("ASK_CONCEAL_D", "a=b=c")
        ProcessEnvironment.conceal { $0 == "ASK_CONCEAL_D" }
        #expect(get("ASK_CONCEAL_D") == "")
    }

    @Test func `the launch snapshot keeps the values that were blanked afterwards`() {
        set("ASK_CONCEAL_E", "before")
        let before = ProcessEnvironment.snapshot()
        ProcessEnvironment.conceal { $0 == "ASK_CONCEAL_E" }
        #expect(before["ASK_CONCEAL_E"] == "before")
        #expect(ProcessEnvironment.snapshot()["ASK_CONCEAL_E"] == "")
    }
}
