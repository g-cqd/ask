internal import AskAI
internal import Foundation

extension ModelsCommand {
    /// Lists the chat models the Antigravity account offers, asking the server and keeping the answer for the runs that follow.
    func showAgy(now: Double) async throws {
        let listing = try await ModelDiscovery.agy().refreshed(now: now)
        ModelTable.print(listing.snapshot, defaultFirst: false, showAll: all)
        if let standard = listing.defaultModelID {
            print("The server's own default is \(standard); ask chooses none, so pass --model.")
        } else {
            print("ask chooses no default, so pass --model.")
        }
    }
}
