/// Zero-pads `self` on the left, for the two-digit hex of a byte.
extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
