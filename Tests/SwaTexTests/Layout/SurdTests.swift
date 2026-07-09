import Testing

@testable import SwaTex

@Suite("Surd")
struct SurdTests {
    /// Breakpoints from KaTeX delimiter sizing: 1.0, 1.2, 1.8, 2.4, 3.0+.
    @Test func fontSelectionBreakpoints() {
        #expect(surdFont(forInnerHeight: 1.0) == .mainRegular)
        #expect(surdFont(forInnerHeight: 1.09) == .mainRegular)
        #expect(surdFont(forInnerHeight: 1.2) == .size1Regular)
        #expect(surdFont(forInnerHeight: 1.49) == .size1Regular)
        #expect(surdFont(forInnerHeight: 1.8) == .size2Regular)
        #expect(surdFont(forInnerHeight: 2.09) == .size2Regular)
        #expect(surdFont(forInnerHeight: 2.4) == .size3Regular)
        #expect(surdFont(forInnerHeight: 2.69) == .size3Regular)
        #expect(surdFont(forInnerHeight: 3.0) == .size4Regular)
        #expect(surdFont(forInnerHeight: 10.0) == .size4Regular)
    }

    @Test func selectSurdHeightSnapsUp() {
        #expect(selectSurdHeight(0.5) == 1.0)
        #expect(selectSurdHeight(1.0) == 1.0)
        #expect(selectSurdHeight(1.01) == 1.2)
        #expect(selectSurdHeight(1.5) == 1.8)
        #expect(selectSurdHeight(2.0) == 2.4)
        #expect(selectSurdHeight(2.5) == 3.0)
        // Beyond the largest size: track the requested height.
        #expect(selectSurdHeight(4.2) == 4.2)
    }
}
