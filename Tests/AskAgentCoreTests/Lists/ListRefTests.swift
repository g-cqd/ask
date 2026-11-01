import Testing

@testable import AskAgentCore

/// Ids as the list tools write them (ADR-0141): one way to write each.
@Suite
struct ListRefTests {
    @Test
    func `t3, t5-t9 and @2 are ids; numbers, other letters, reversed or huge ranges are not`() {
        #expect(ListRef("t3", prefix: "t") == .id(3))
        #expect(ListRef("t5-t9", prefix: "t") == .range(5 ... 9))
        #expect(ListRef("@2", prefix: "t") == .added(2))
        for bad in ["3", "i3", "t0", "t9-t5", "t1-t5000", "t", "@0", "@x", "t3-", "-t3", "t1-t2-t3"] {
            #expect(ListRef(bad, prefix: "t") == nil, "\(bad)")
        }
        #expect(ListRef.list("t1 t3-t4 @1", prefix: "t") == [.id(1), .range(3 ... 4), .added(1)])
        #expect(ListRef.list("t1 x", prefix: "t") == nil)
    }

    @Test
    func `ids are written as runs, counted once there are several`() {
        #expect(ListRef.runs([9, 3, 5, 6, 7], prefix: "t") == "t3 t5–t7 t9")
        #expect(ListRef.counted("done", [2, 1, 1], prefix: "t") == "done t1–t2 (2)")
        #expect(ListRef.counted("done", [4], prefix: "i") == "done i4")
    }
}
