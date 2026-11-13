/// A provider and model the user chose with `/model`: the top layer, for this run only. Both are kept because a
/// model id means nothing without the provider that serves it, and a later configuration edit must not swap one.
struct ModelSelection: Sendable, Equatable {
    let provider: String
    let model: String
}
