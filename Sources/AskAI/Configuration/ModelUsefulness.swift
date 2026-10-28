/// Which catalogued models are useful for ask (roadmap 0089): one rule for every provider.
///
/// A model is useful unless its catalog entry says it is not (``CatalogModel/unsuitable``): an image, audio, embedding or tab-completion
/// model, one without tool calls, or one the provider hides. A catalog that says nothing leaves the model in, because a model that works must
/// not be hidden for want of a flag. There is no context floor: nothing recorded supports a number.
public enum ModelUsefulness {
    /// `models`, without the ones the catalog marks as of no use when `onlyUseful`; all of them otherwise.
    /// - Parameters:
    ///   - models: a provider's catalog.
    ///   - onlyUseful: the `ui.onlyUsefulModels` setting.
    /// - Returns: the models to list or choose from.
    public static func shown(_ models: [CatalogModel], onlyUseful: Bool) -> [CatalogModel] {
        onlyUseful ? models.filter { $0.unsuitable == nil } : models
    }

    /// The models the filter hides, each with its reason.
    /// - Parameter models: a provider's catalog.
    /// - Returns: the hidden models.
    public static func hidden(_ models: [CatalogModel]) -> [CatalogModel] { models.filter { $0.unsuitable != nil } }
}
