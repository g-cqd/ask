/// A hue of the session's own (roadmap 0164): from a seed (the project's path and the session file's name), the same every time, spread
/// over the colour wheel by FNV-1a, at a saturation and a brightness that read as a colour on both light and dark pages once mixed.
enum SessionHue {
    /// The seed's angle on the colour wheel, 0 to 359.
    static func degrees(seed: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % 360)
    }

    /// The hue as red, green and blue from 0 to 255.
    static func rgb(seed: String) -> SIMD3<Double> {
        let hue = Double(degrees(seed: seed)) / 60
        let (saturation, value) = (0.75, 1.0)
        let chroma = value * saturation
        let x = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - chroma
        let (r, g, b): (Double, Double, Double) =
            switch Int(hue) {
                case 0: (chroma, x, 0)
                case 1: (x, chroma, 0)
                case 2: (0, chroma, x)
                case 3: (0, x, chroma)
                case 4: (x, 0, chroma)
                default: (chroma, 0, x)
            }
        return SIMD3((r + m) * 255, (g + m) * 255, (b + m) * 255)
    }
}
