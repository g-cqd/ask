internal import AskAI
internal import Foundation

extension ModelsCommand {
    /// Lists the chat models the Antigravity account offers. Nothing is cached yet, so each listing asks the server.
    func showAgy(now: Double) async throws {
        let transport = URLSessionTransport()
        let session = try await makeAgyAccess(transport: transport).session(now: now)
        let list = try await AgyCloudClient(transport: transport)
            .models(accessToken: session.accessToken, project: session.projectID)
        ModelTable.print(CatalogSnapshot(models: list.models), defaultFirst: false)
        if let standard = list.defaultModelID {
            print("The server's own default is \(standard); ask chooses none, so pass --model.")
        } else {
            print("ask chooses no default, so pass --model.")
        }
    }
}
