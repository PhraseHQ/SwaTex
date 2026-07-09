// SwaTex demo gallery — run with `swift run SwaTexDemo` (macOS).
//
// Renders a formula gallery with live font-size control, inline/display
// toggle, and a LaTeX playground field — all native SwiftUI + CoreText,
// no WebView.

import SwaTex
import SwaTexRender
import SwiftUI

@main
struct SwaTexDemoApp: App {
    var body: some Scene {
        WindowGroup("SwaTex") {
            GalleryView()
        }
    }
}

struct GalleryView: View {
    @State private var fontSize: Double = 24
    @State private var inline = false
    @State private var playground = #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#

    private static let formulas: [(String, String)] = [
        ("Quadratic formula", #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#),
        ("Basel problem", #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#),
        ("Gaussian integral", #"\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}"#),
        ("Euler's identity", #"e^{i\pi} + 1 = 0"#),
        ("Eigenvalues", #"\det\begin{pmatrix} a-\lambda & b \\ c & d-\lambda \end{pmatrix} = 0"#),
        ("Chemistry (mhchem)", #"\ce{2H2 + O2 ->[\Delta] 2H2O}"#),
        ("Maxwell", #"\nabla \times \vec{B} = \mu_0 \vec{J} + \mu_0 \varepsilon_0 \frac{\partial \vec{E}}{\partial t}"#),
        ("Binomial", #"\binom{n}{k} = \frac{n!}{k!(n-k)!}"#),
        ("Cases", #"|x| = \begin{cases} x & x \ge 0 \\ -x & x < 0 \end{cases}"#),
        ("Limits", #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#),
    ]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    playgroundSection
                    ForEach(Self.formulas, id: \.0) { name, latex in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MathView(latex)
                                .font(size: fontSize)
                                .inlineStyle(inline)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Text("Size")
            Slider(value: $fontSize, in: 12...64) {
                Text("Font size")
            }
            .frame(width: 200)
            Text("\(Int(fontSize)) pt")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            Toggle("Inline style", isOn: $inline)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var playgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playground")
                .font(.caption)
                .foregroundStyle(.secondary)
            #if os(watchOS)
                TextField("LaTeX", text: $playground)
                    .font(.body.monospaced())
            #else
                TextField("LaTeX", text: $playground, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            #endif
            MathView(playground)
                .font(size: fontSize)
                .inlineStyle(inline)
        }
    }
}

#Preview {
    GalleryView()
}
