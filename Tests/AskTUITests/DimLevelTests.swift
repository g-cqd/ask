import TerminalKitCodecs
import TerminalKitStyle
import Testing

@testable import AskTUI

/// Note n13: secondary text can be fainter than ask's own grey, `ui.dim` "faint" or "fainter", and a shimmering header stays fainter
/// than the dim around it.
@Suite("Secondary text can be fainter")
struct DimLevelTests {
    private static let page = TerminalPage(background: SIMD3(255, 255, 255), foreground: SIMD3(0, 0, 0))

    private func grey(_ dim: ScreenDim, page: TerminalPage = Self.page) -> Double? {
        let theme = ScreenTheme(page: page, dim: dim)
        guard case .rgb(let r, _, _) = theme.legible(Style(dim: true)).fg else { return nil }
        return Double(r)
    }

    @Test func `each step is nearer the page`() throws {
        let normal = try #require(grey(.normal))
        let faint = try #require(grey(.faint))
        let fainter = try #require(grey(.fainter))
        #expect(normal < faint && faint < fainter, "\(normal), \(faint), \(fainter)")
    }

    @Test func `the shimmer's faint header stays below the chosen dim`() throws {
        for dim in [ScreenDim.normal, .faint, .fainter] {
            let theme = ScreenTheme(page: Self.page, dim: dim)
            guard case .rgb(let base, _, _) = theme.shimmerBase, let shown = grey(dim) else {
                Issue.record("not a colour")
                continue
            }
            #expect(Double(base) > shown, "\(dim): \(base) against \(shown)")
        }
    }

    @Test func `too faint to read, it keeps ask's own grey`() {
        // A low-contrast page, where 50% would read below 3:1.
        let low = TerminalPage(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))
        #expect(ScreenTheme(page: low, dim: .fainter).secondary == ScreenTheme(page: low, dim: .normal).secondary)
    }
}
