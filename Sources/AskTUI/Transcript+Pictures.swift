/// Pictures folded away (roadmap 0208; the owner, 2026-11-06: a picture shows at once, and folds on a click). A folded picture keeps
/// its line; the tool's output folds apart from it.
extension Transcript {
    /// Whether the picture at `position` of block `block` is folded away.
    func isPictureFolded(_ position: Int, at block: Int) -> Bool {
        foldedPictures[block]?.contains(position) == true
    }

    /// Folds the picture at `position` of block `block` away, or shows it again.
    mutating func togglePicture(_ position: Int, at block: Int) {
        guard toolImages[block]?.indices.contains(position) == true else { return }
        if foldedPictures[block, default: []].remove(position) == nil {
            foldedPictures[block, default: []].insert(position)
        }
        if foldedPictures[block]?.isEmpty == true { foldedPictures[block] = nil }
        revisions[block] = bump()
    }

    /// Block `block`'s placements as drawn: none for a picture folded away, so only its line shows.
    func shownPlacements(at block: Int) -> [ImagePlacement?] {
        let placements = imagePlacements[block] ?? []
        guard let folded = foldedPictures[block] else { return placements }
        return placements.enumerated().map { folded.contains($0.offset) ? nil : $0.element }
    }
}
