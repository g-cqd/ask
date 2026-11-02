internal import Testing

@testable import AskTUI

/// Each piece of the characterisation's alphabet alone, in a few places, with its own digest: when the whole digest differs on a machine
/// (CI's macOS 26 runner did, from the start), these say which piece renders differently there.
@Suite("Each piece of random Markdown renders as it did")
struct MarkdownRowPieceTests {
    static func messages(_ piece: String) -> [String] {
        [piece, "a\(piece)b", "x \(piece) y \(piece)\(piece)", "- \(piece)\n\n\(piece) z", "**\(piece)** `\(piece)`"]
    }

    static let digests: [UInt64] = [
        4_844_608_142_932_241_053, 16_597_068_946_732_303_403, 13_793_541_650_141_622_821, 13_793_541_650_141_622_821,
        7_401_690_168_131_445_251, 8_950_606_938_426_359_393, 14_415_774_673_608_627_367, 4_693_507_509_456_761_255,
        14_233_468_803_209_438_319, 10_688_067_269_713_611_041, 17_183_191_118_331_653_649, 13_137_085_324_392_749_027,
        5_035_454_425_306_487_835, 14_752_455_346_232_888_633, 14_792_070_077_191_667_751, 1_871_885_445_023_077_949,
        14_655_019_957_048_146_269, 12_189_091_257_266_286_355, 4_894_969_315_309_879_267, 14_466_461_178_691_220_211,
        3_924_163_066_345_989_541, 5_542_740_867_277_035_495, 5_019_635_557_223_753_151, 7_118_785_121_975_288_771,
        15_005_094_104_543_236_269, 8_620_541_366_743_082_903, 9_037_708_773_150_222_663
    ]

    @Test(arguments: MarkdownRowCharacterisationTests.alphabet.indices)
    func `each piece keeps its digest`(index: Int) {
        let piece = MarkdownRowCharacterisationTests.alphabet[index]
        let digest = MarkdownRowCharacterisationTests.digest(Self.messages(piece))
        #expect(digest == Self.digests[index], "piece \(index): \(piece.debugDescription)")
    }
}
