extension String {
    /// Whether `self` is two to four dot-separated numbers of at most six digits each, so that nothing but a version can reach a header
    /// from a place that is not ours.
    var isPlainVersion: Bool {
        let parts = split(separator: ".", omittingEmptySubsequences: false)
        return (2 ... 4).contains(parts.count)
            && parts.allSatisfy { part in
                (1 ... 6).contains(part.count) && part.allSatisfy { $0.isASCII && $0.isNumber }
            }
    }
}
