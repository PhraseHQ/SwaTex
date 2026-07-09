import Foundation
import Testing

@testable import SwaTex
@testable import SwaTexRender

/// Emits sample PNGs for visual inspection when SWATEX_EMIT_SAMPLES is set.
@Suite("SampleEmit", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_EMIT_SAMPLES"] != nil))
struct SampleEmitTests {
    @Test func emitSamples() throws {
        let dir = ProcessInfo.processInfo.environment["SWATEX_EMIT_SAMPLES"]!
        let formulas = [
            #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
            #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#,
            #"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#,
            #"\begin{pmatrix} a & b \\ c & d \end{pmatrix} \cdot \vec{x} = \lambda \vec{x}"#,
        ]
        for (i, f) in formulas.enumerated() {
            let png = try #require(
                try ImageRenderer.png(
                    latex: f,
                    options: RenderOptions(fontSize: 48, padding: 12, backgroundColor: .white)))
            try png.write(to: URL(fileURLWithPath: "\(dir)/sample\(i).png"))
        }
    }
}
