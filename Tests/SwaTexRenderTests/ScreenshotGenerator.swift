#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import SwiftUI
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// README screenshot generator (not a test of behavior). Run with
    /// `SWATEX_SCREENSHOTS=<output dir> swift test --filter Screenshot`
    /// to regenerate `.github/assets/showcase-{light,dark}.png`.
    /// Headless: offscreen window + `cacheDisplay`, deterministic content.
    @Suite(
        "ScreenshotGenerator",
        .enabled(if: ProcessInfo.processInfo.environment["SWATEX_SCREENSHOTS"] != nil),
        .serialized)
    @MainActor
    struct ScreenshotGenerator {

        // MARK: Showcase content

        private struct SectionLabel: View {
            let text: String
            var body: some View {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private struct InlineLine: View {
            let parts: [Part]
            enum Part {
                case text(String)
                case math(String)
            }

            var body: some View {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        switch part {
                        case .text(let s):
                            Text(s).font(.system(size: 16))
                                .lineLimit(1).fixedSize()
                        case .math(let m):
                            MathView(m).font(size: 16).inlineStyle()
                                .mathColor(.primary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }

        private struct Display: View {
            let latex: String
            var size: CGFloat = 19
            var body: some View {
                HStack {
                    Spacer(minLength: 0)
                    MathView(latex).font(size: size).mathColor(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }

        private struct ShowcaseView: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SwaTex")
                        .font(.system(size: 34, weight: .bold))
                    Text("PURE SWIFT · NATIVE MATH ON EVERY APPLE PLATFORM")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 13) {
                        SectionLabel(text: "Inline layout · baseline alignment")
                        InlineLine(parts: [
                            .text("Einstein showed that "), .math(#"E = mc^2"#),
                            .text(", where "), .math(#"c"#), .text(" is the"),
                        ])
                        InlineLine(parts: [.text("speed of light.")])
                        InlineLine(parts: [
                            .text("A circle of radius "), .math(#"r"#),
                            .text(" has area "), .math(#"S = \pi r^2"#),
                            .text(" and"),
                        ])
                        InlineLine(parts: [
                            .text("circumference "), .math(#"C = 2\pi r"#), .text("."),
                        ])
                        InlineLine(parts: [
                            .text("The golden ratio "),
                            .math(#"\varphi = \frac{1+\sqrt{5}}{2}"#),
                            .text(" satisfies "), .math(#"\varphi^2 = \varphi + 1"#),
                            .text("."),
                        ])

                        Divider()

                        SectionLabel(text: "Fourier transform")
                        Display(latex: #"\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x)\, e^{-2\pi i x \xi}\, dx"#)

                        Divider()

                        SectionLabel(text: "3D rotation matrix")
                        Display(
                            latex: #"R_z(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta & 0 \\ \sin\theta & \cos\theta & 0 \\ 0 & 0 & 1 \end{pmatrix}"#)

                        Divider()

                        SectionLabel(text: "Schrödinger equation")
                        Display(
                            latex: #"i\hbar \frac{\partial}{\partial t} \Psi = \left[ -\frac{\hbar^2}{2m} \nabla^2 + V \right] \Psi"#)

                        Divider()

                        SectionLabel(text: "Chemistry — mhchem built in")
                        Display(
                            latex: #"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#, size: 17)
                        Display(
                            latex: #"\ce{Zn^2+ <=>[+ 2OH-][+ 2H+] Zn(OH)2 v}"#, size: 17)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2))

                    Text("Rendered natively by SwaTex — no JavaScript, no WebView.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(22)
                .frame(width: 420)
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }

        // MARK: Capture

        private func capture(appearance: NSAppearance.Name, to url: URL) throws {
            let hosting = NSHostingView(rootView: ShowcaseView())
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)

            let window = NSWindow(
                contentRect: hosting.frame, styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))

            let rep = try #require(
                hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: url)
            window.orderOut(nil)
            print("SCREENSHOT wrote \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }

        @Test func generate() throws {
            let dir = URL(
                fileURLWithPath: ProcessInfo.processInfo.environment["SWATEX_SCREENSHOTS"]!)
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try capture(appearance: .aqua, to: dir.appendingPathComponent("showcase-light.png"))
            try capture(
                appearance: .darkAqua, to: dir.appendingPathComponent("showcase-dark.png"))
        }
    }
#endif
