/// Where a byte cut through UTF-8 text may fall without leaving half a character (roadmap 0057, ADR-0083).
///
/// Output is kept and clipped by bytes, the first and last of a stream with a count of what fell between. A character of two to four
/// bytes that straddles a cut becomes U+FFFD when each side is decoded alone, so the model reads garbage where valid text was
/// printed. These move a cut to a character boundary, giving up at most three bytes of the budget on each side. Bytes that are not
/// text are cut the same way and never crash: nothing here decides whether the input is valid.
public enum UTF8Cut {
    /// `bytes` without a character that was cut off at its end.
    /// - Parameter bytes: a stretch of UTF-8 that ends where the cut was made.
    /// - Returns: `bytes`, shortened by the bytes of an incomplete last character, if it has one.
    public static func droppingPartialEnd(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var lead = bytes.endIndex
        while lead > bytes.startIndex, bytes.endIndex - lead < 4 {
            lead -= 1
            if !isContinuation(bytes[lead]) { break }
        }
        guard lead < bytes.endIndex, !isContinuation(bytes[lead]),
            bytes.endIndex - lead < length(startingWith: bytes[lead])
        else { return bytes }
        return bytes[..<lead]
    }

    /// `bytes` without the end of a character that was cut off before its start.
    /// - Parameter bytes: a stretch of UTF-8 that starts where the cut was made.
    /// - Returns: `bytes`, shortened by up to three continuation bytes at its start.
    public static func droppingPartialStart(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var start = bytes.startIndex
        while start < bytes.endIndex, start - bytes.startIndex < 3, isContinuation(bytes[start]) { start += 1 }
        return bytes[start...]
    }

    private static func isContinuation(_ byte: UInt8) -> Bool { byte & 0b1100_0000 == 0b1000_0000 }

    /// How many bytes a character that starts with `byte` has, one for anything that is not a lead byte.
    private static func length(startingWith byte: UInt8) -> Int {
        switch byte {
            case 0xC0 ... 0xDF: 2
            case 0xE0 ... 0xEF: 3
            case 0xF0 ... 0xF7: 4
            default: 1
        }
    }
}
