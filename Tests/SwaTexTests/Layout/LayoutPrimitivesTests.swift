import Testing

@testable import SwaTex

@Suite("Spacing")
struct SpacingTests {
    @Test func ordBinSpacing() {
        #expect(atomSpacing(.ord, .bin, tight: false) == 4.0)
    }

    @Test func ordRelSpacing() {
        #expect(atomSpacing(.ord, .rel, tight: false) == 5.0)
    }

    @Test func ordOrdNoSpacing() {
        #expect(atomSpacing(.ord, .ord, tight: false) == 0.0)
    }

    @Test func tightEliminatesMostSpacing() {
        #expect(atomSpacing(.ord, .bin, tight: true) == 0.0)
        #expect(atomSpacing(.ord, .rel, tight: true) == 0.0)
    }

    @Test func tightKeepsOpSpacing() {
        #expect(atomSpacing(.ord, .op, tight: true) == 3.0)
        #expect(atomSpacing(.op, .ord, tight: true) == 3.0)
    }

    @Test func muToEmConversion() {
        let quad = 1.0
        #expect(abs(muToEm(3, quad: quad) - 3.0 / 18.0) < 1e-10)
        #expect(abs(muToEm(4, quad: quad) - 4.0 / 18.0) < 1e-10)
        #expect(abs(muToEm(5, quad: quad) - 5.0 / 18.0) < 1e-10)
    }
}

@Suite("HBox")
struct HBoxTests {
    @Test func emptyHBox() {
        let hbox = makeHBox([])
        #expect(hbox.width == 0)
        #expect(hbox.height == 0)
        #expect(hbox.depth == 0)
    }

    @Test func singleChildHBox() {
        let child = LayoutBox(width: 0.5, height: 0.43, depth: 0, content: .empty)
        let hbox = makeHBox([child])
        #expect(abs(hbox.width - 0.5) < 1e-10)
        #expect(abs(hbox.height - 0.43) < 1e-10)
    }

    @Test func twoChildrenWidthSums() {
        let a = LayoutBox(width: 0.5, height: 0.43, depth: 0, content: .empty)
        let b = LayoutBox(width: 0.6, height: 0.69, depth: 0.1, content: .empty)
        let hbox = makeHBox([a, b])
        #expect(abs(hbox.width - 1.1) < 1e-10)
        #expect(abs(hbox.height - 0.69) < 1e-10)
        #expect(abs(hbox.depth - 0.1) < 1e-10)
    }
}

@Suite("VBox")
struct VBoxTests {
    private func makeTestBox(_ w: Double, _ h: Double, _ d: Double) -> LayoutBox {
        LayoutBox(width: w, height: h, depth: d, content: .empty)
    }

    @Test func emptyVBox() {
        let vbox = makeVBox([])
        #expect(vbox.width == 0)
        #expect(vbox.height == 0)
    }

    @Test func singleElementVBox() {
        let vbox = makeVBox([VBoxChild(.box(makeTestBox(1.0, 0.5, 0.2)))])
        #expect(abs(vbox.width - 1.0) < 1e-10)
        #expect(abs(vbox.height - 0.7) < 1e-10)
    }

    @Test func vboxWithKern() {
        let vbox = makeVBox([
            VBoxChild(.box(makeTestBox(1.0, 0.5, 0.2))),
            VBoxChild(.kern(0.1)),
            VBoxChild(.box(makeTestBox(0.8, 0.3, 0.1))),
        ])
        #expect(abs(vbox.width - 1.0) < 1e-10)
        // total = (0.5+0.2) + 0.1 + (0.3+0.1) = 1.2
        #expect(abs(vbox.height - 1.2) < 1e-10)
    }

    @Test func vboxWithDepth() {
        let vbox = makeVBox(
            [VBoxChild(.box(makeTestBox(1.0, 0.8, 0.4)))], depthBelowBaseline: 0.5)
        #expect(abs(vbox.height - 0.7) < 1e-10)
        #expect(abs(vbox.depth - 0.5) < 1e-10)
    }
}
