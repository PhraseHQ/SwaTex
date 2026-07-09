import CoreGraphics
import Foundation
import Testing

@testable import SwaTex
@testable import SwaTexRender

/// Render performance benchmarks (results logged to the performance log).
/// Enabled via SWATEX_BENCH=1 so normal test runs stay fast.
@Suite("RenderBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil), .serialized)
struct RenderBenchmarks {
    static let formulas: [String] = [
        #"x^2 + y^2 = z^2"#,
        #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
        #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#,
        #"\int_0^1 x^2\,dx"#,
        #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
        #"\lim_{x \to 0} \frac{\sin x}{x}"#,
        #"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#,
        #"\left( \frac{a}{b} \right)^n"#,
        #"\hat{x} + \vec{v}"#,
        #"\mathbb{R} \subset \mathbb{C}"#,
    ]

    @Test func coldVsHotFontCache() throws {
        let list = try SwaTexEngine.displayList(for: Self.formulas[1])
        let opts = RenderOptions(fontSize: 40)

        // Cold: first render in the process pays font descriptor creation.
        let coldStart = ContinuousClock.now
        _ = ImageRenderer.image(for: list, options: opts)
        let cold = ContinuousClock.now - coldStart

        // Hot: steady state.
        let n = 50
        let hotStart = ContinuousClock.now
        for _ in 0..<n {
            _ = ImageRenderer.image(for: list, options: opts)
        }
        let hot = (ContinuousClock.now - hotStart) / n

        print("BENCH coldRender=\(cold) hotRender(avg of \(n))=\(hot)")
        #expect(hot < .milliseconds(50))
    }

    @Test func pngBatch100() throws {
        // Warm the caches first.
        _ = try ImageRenderer.png(latex: Self.formulas[0])

        let start = ContinuousClock.now
        var total = 0
        for i in 0..<100 {
            let latex = Self.formulas[i % Self.formulas.count]
            let png = try #require(
                try ImageRenderer.png(
                    latex: latex, options: RenderOptions(fontSize: 40), displayScale: 2))
            total += png.count
        }
        let elapsed = ContinuousClock.now - start
        print("BENCH pngBatch100 total=\(elapsed) avg=\(elapsed / 100) bytes=\(total)")
        #expect(elapsed < .seconds(10))
    }

    @Test func phaseBreakdown() throws {
        let n = 2000
        var parseTotal = Duration.zero
        var layoutTotal = Duration.zero
        var displayTotal = Duration.zero

        for i in 0..<n {
            let latex = Self.formulas[i % Self.formulas.count]

            let t0 = ContinuousClock.now
            let ast = try parseLaTeX(latex)
            let t1 = ContinuousClock.now
            let box = layout(ast, options: LayoutOptions())
            let t2 = ContinuousClock.now
            _ = toDisplayList(box)
            let t3 = ContinuousClock.now

            parseTotal += t1 - t0
            layoutTotal += t2 - t1
            displayTotal += t3 - t2
        }
        print(
            "BENCH phases n=\(n) parse=\(parseTotal / n) layout=\(layoutTotal / n) "
                + "display=\(displayTotal / n)")
        #expect(parseTotal + layoutTotal + displayTotal < .seconds(5))
    }

    @Test func formulaCacheSpeedup() throws {
        let cache = FormulaCache(capacity: 64)
        let latex = Self.formulas[1]
        _ = try SwaTexEngine.displayList(for: latex, cache: cache)  // prime

        let n = 10_000
        let cachedStart = ContinuousClock.now
        for _ in 0..<n {
            _ = try SwaTexEngine.displayList(for: latex, cache: cache)
        }
        let cached = (ContinuousClock.now - cachedStart) / n

        let uncachedStart = ContinuousClock.now
        for _ in 0..<100 {
            _ = try SwaTexEngine.displayList(for: latex, cache: nil)
        }
        let uncached = (ContinuousClock.now - uncachedStart) / 100

        print("BENCH cacheHit=\(cached) uncached=\(uncached) speedup=\(uncached / cached)x")
        #expect(cached < uncached)
    }

    @Test func parallelBatchSpeedup() async throws {
        // 1000 distinct formulas (no cache) — serial vs TaskGroup.
        let formulas = (0..<1000).map { i in
            "\(Self.formulas[i % Self.formulas.count]) + q_{\(i)}"
        }

        let serialStart = ContinuousClock.now
        for f in formulas {
            _ = try? SwaTexEngine.displayList(for: f)
        }
        let serial = ContinuousClock.now - serialStart

        let parallelStart = ContinuousClock.now
        _ = await SwaTexEngine.displayLists(for: formulas)
        let parallel = ContinuousClock.now - parallelStart

        print("BENCH batch1000 serial=\(serial) parallel=\(parallel) speedup=\(serial / parallel)x")
        #expect(parallel < serial)
    }

    @Test func parseLayoutThroughput() throws {
        // Pure engine throughput without rasterization, steady state.
        let n = 1000
        var items = 0
        let start = ContinuousClock.now
        for i in 0..<n {
            let latex = Self.formulas[i % Self.formulas.count]
            let list = try SwaTexEngine.displayList(for: latex)
            items += list.items.count
        }
        let elapsed = ContinuousClock.now - start
        print("BENCH parseLayout n=\(n) total=\(elapsed) perFormula=\(elapsed / n) items=\(items)")
        #expect(elapsed < .seconds(5))
    }
}

@Suite("SVGBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil))
struct SVGBenchmarks {
    @Test func svgRenderThroughput() throws {
        let lists = try RenderBenchmarks.formulas.map {
            try SwaTexEngine.displayList(for: $0)
        }
        let renderer = SVGRenderer()
        // Warm up
        _ = renderer.render(lists[0])

        let n = 2000
        var bytes = 0
        let start = ContinuousClock.now
        for i in 0..<n {
            bytes += renderer.render(lists[i % lists.count]).utf8.count
        }
        let elapsed = ContinuousClock.now - start
        print("BENCH svgRender n=\(n) perFormula=\(elapsed / n) bytes=\(bytes)")
    }
}

@Suite("DrawBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil))
struct DrawBenchmarks {
    @Test func drawVsContextCreation() throws {
        let list = try SwaTexEngine.displayList(for: RenderBenchmarks.formulas[1])
        let opts = RenderOptions(fontSize: 40)
        let m = DisplayListRenderer.metrics(for: list, options: opts)
        let scale: CGFloat = 2
        let w = Int((m.width * scale).rounded(.up)), h = Int((m.height * scale).rounded(.up))

        func makeCtx() -> CGContext {
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            return ctx
        }

        // Context creation only
        let n = 200
        var t0 = ContinuousClock.now
        for _ in 0..<n { _ = makeCtx() }
        let ctxTime = (ContinuousClock.now - t0) / n

        // Draw only (context reused)
        let ctx = makeCtx()
        _ = DisplayListRenderer.draw(list, in: ctx, options: opts)  // warm
        t0 = ContinuousClock.now
        for _ in 0..<1000 { DisplayListRenderer.draw(list, in: ctx, options: opts) }
        let drawTime = (ContinuousClock.now - t0) / 1000

        // makeImage only
        t0 = ContinuousClock.now
        for _ in 0..<n { _ = ctx.makeImage() }
        let imgTime = (ContinuousClock.now - t0) / n

        print("BENCH drawBreakdown ctxCreate=\(ctxTime) drawOnly=\(drawTime) makeImage=\(imgTime)")
    }
}

@Suite("CorpusPNGBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_CORPUS"] != nil))
struct CorpusPNGBenchmarks {
    @Test func corpusPNGToDisk() throws {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["SWATEX_CORPUS"]!
        let outDir = env["SWATEX_OUT"] ?? "/tmp/swout"
        try? FileManager.default.createDirectory(
            atPath: outDir, withIntermediateDirectories: true)
        let formulas = try String(contentsOfFile: corpus, encoding: .utf8)
            .split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("%") }

        // Warm caches (fonts) outside the timed region, like RaTeX's loaded font set.
        _ = try ImageRenderer.png(latex: "x")

        let start = ContinuousClock.now
        var count = 0
        for (i, f) in formulas.enumerated() {
            guard
                let png = try? ImageRenderer.png(
                    latex: f, options: RenderOptions(fontSize: 40), displayScale: 2)
            else { continue }
            try png.write(to: URL(fileURLWithPath: "\(outDir)/\(i).png"))
            count += 1
        }
        let elapsed = ContinuousClock.now - start
        print("BENCH corpusPNG n=\(count) total=\(elapsed) perFormula=\(elapsed / max(count, 1))")
    }
}

@Suite("EncodeBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil))
struct EncodeBenchmarks {
    @Test func pngEncodeShare() throws {
        let list = try SwaTexEngine.displayList(for: #"\frac{a+b}{c}"#)
        let image = ImageRenderer.image(
            for: list, options: RenderOptions(fontSize: 40), displayScale: 2)!
        let n = 300
        let start = ContinuousClock.now
        for _ in 0..<n { _ = ImageRenderer.pngData(image) }
        let encode = (ContinuousClock.now - start) / n
        print("BENCH pngEncodeOnly=\(encode) imageSize=\(image.width)x\(image.height)")
    }
}

@Suite("FastPNGBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil))
struct FastPNGBenchmarks {
    @Test func fastVsImageIO() throws {
        let list = try SwaTexEngine.displayList(for: #"\frac{a+b}{c}"#)
        let opts = RenderOptions(fontSize: 40)
        let n = 200

        var t0 = ContinuousClock.now
        for _ in 0..<n { _ = ImageRenderer.png(for: list, options: opts) }
        let fast = (ContinuousClock.now - t0) / n

        t0 = ContinuousClock.now
        for _ in 0..<n {
            _ = ImageRenderer.image(for: list, options: opts).flatMap(ImageRenderer.pngData)
        }
        let imageio = (ContinuousClock.now - t0) / n

        let fastBytes = ImageRenderer.png(for: list, options: opts)!.count
        let ioBytes = ImageRenderer.image(for: list, options: opts)
            .flatMap(ImageRenderer.pngData)!.count
        print("BENCH fastPNG=\(fast) imageIO=\(imageio) bytes fast=\(fastBytes) io=\(ioBytes)")
    }
}

@Suite("ParallelPNGBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_CORPUS"] != nil))
struct ParallelPNGBenchmarks {
    @Test func corpusParallelPNG() async throws {
        let corpus = ProcessInfo.processInfo.environment["SWATEX_CORPUS"]!
        let formulas = try String(contentsOfFile: corpus, encoding: .utf8)
            .split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("%") }
        _ = try ImageRenderer.png(latex: "x")  // warm fonts

        let start = ContinuousClock.now
        let results = await ImageRenderer.pngs(for: formulas)
        let elapsed = ContinuousClock.now - start
        let ok = results.compactMap { $0 }.count
        print("BENCH parallelCorpusPNG n=\(ok) total=\(elapsed) perFormula=\(elapsed / max(ok, 1))")
    }
}
