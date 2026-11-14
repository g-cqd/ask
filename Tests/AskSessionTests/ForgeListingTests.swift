import AskTUI
import AskTools
import Synchronization
import Testing

@testable import AskSession

/// The `#` picker's pull requests and issues and the status bar's pull request (roadmap 0186), read by whatever the listing is given:
/// a child process when ask runs (ADR-0152), a closure here.
@Suite("The workspace's pull requests and issues are read once, off the screen, when due")
struct ForgeListingTests {
    @Test func `a read fills the picker's rows and tells the screen the list and the branch's pull request`() async {
        let asked = Mutex<[String]>([])
        let listing = ForgeListing { workspace in
            asked.withLock { $0.append(workspace) }
            let printed =
                #"{"open":[{"number":42,"kind":"pull request","title":"Work"},"#
                + #"{"number":7,"kind":"issue","title":"Bug"}],"pullRequest":42}"#
            return ForgeSnapshot(json: Array(printed.utf8)) ?? ForgeSnapshot()
        }
        let seen = Mutex<[String]>([])
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            listing.request(in: "/work") { update in
                switch update {
                    case .choicesStale(let command): seen.withLock { $0.append("stale \(command)") }
                    case .branchPullRequest(let number):
                        seen.withLock { $0.append("pull \(number ?? 0)") }
                        done.resume()
                    default: break
                }
            }
        }
        #expect(asked.withLock { $0 } == ["/work"])
        #expect(seen.withLock { $0 } == ["stale #", "pull 42"])
        #expect(listing.rows.map(\.label) == ["#42", "#7"])
        #expect(listing.rows.map(\.detail) == ["pull request · Work", "issue · Bug"])
        #expect(listing.rows.map(\.arguments) == ["#42", "#7"])
    }

    @Test func `nothing found empties the rows and clears the pull request`() async {
        let listing = ForgeListing { _ in ForgeSnapshot() }
        let pull = await withCheckedContinuation { (done: CheckedContinuation<Int?, Never>) in
            listing.request(in: "/work") { update in
                if case .branchPullRequest(let number) = update { done.resume(returning: number) }
            }
        }
        #expect(pull == nil)
        #expect(listing.rows.isEmpty)
    }

    @Test func `a read is due at first, and again five minutes after the last`() {
        let now = ContinuousClock.now
        #expect(ForgeListing.isDue(lastRead: nil, now: now))
        #expect(!ForgeListing.isDue(lastRead: now - .seconds(299), now: now))
        #expect(ForgeListing.isDue(lastRead: now - .seconds(300), now: now))
        #expect(ForgeListing.interval == .seconds(300))
    }
}
