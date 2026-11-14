import AemiSearch

/// A session's search index (`SearchIndex(serialized:)`): a file beside the session, read back at the next search. Promised: bytes
/// that are no index are refused, never trusted; an index that reads can be searched and written again, and reads back the same.
let fuzzIndex: @Sendable ([UInt8]) -> Void = { bytes in
    guard let index = try? SearchIndex(serialized: bytes) else { return }
    let hits = index.search(SearchQuery("cache key error", limit: 5))
    let again = index.serialized()
    guard let copy = try? SearchIndex(serialized: again) else { broken("index: what it wrote does not read back") }
    if copy.count != index.count || copy.termCount != index.termCount {
        broken("index: it read back with other counts")
    }
    if copy.search(SearchQuery("cache key error", limit: 5)) != hits {
        broken("index: it read back with other results")
    }
}
