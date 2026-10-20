/// A catalog failure, reported without the server's potentially credential-bearing body.
public enum ModelCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    case refused(status: Int)
    case invalidResponse
    case noModels
    case cache(path: String)

    public var description: String {
        switch self {
            case .refused(let status):
                "the model catalog was refused (HTTP \(status)); pass --model to choose explicitly"
            case .invalidResponse: "the model catalog is not a valid response; pass --model to choose explicitly"
            case .noModels: "the model catalog lists no usable models; pass --model to choose explicitly"
            case .cache(let path):
                "cannot read or save the model catalog at \(path); run `ask models NAME` for that provider to refresh it"
        }
    }
}
