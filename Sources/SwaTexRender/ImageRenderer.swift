import CoreGraphics
import Foundation
import ImageIO
import SwaTex
import UniformTypeIdentifiers

/// Render LaTeX / display lists to `CGImage` and PNG data.
public enum ImageRenderer {
    /// Render a display list and encode PNG in one pass.
    ///
    /// Uses ``FastPNGEncoder`` (Accelerate + libcompression) straight from
    /// the bitmap context's backing store — no intermediate `CGImage`, no
    /// ImageIO. ~4× faster than the general-purpose encoder (B-006 in
    /// the performance log); output verified pixel-identical via round-trip
    /// decode in FastPNGTests.
    public static func png(
        for list: DisplayList,
        options: RenderOptions = RenderOptions(),
        displayScale: CGFloat = 2
    ) -> Data? {
        let m = DisplayListRenderer.metrics(for: list, options: options)
        let pixelWidth = max(Int((m.width * displayScale).rounded(.up)), 1)
        let pixelHeight = max(Int((m.height * displayScale).rounded(.up)), 1)

        guard
            let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            // INTENTIONALLY UNCOVERED: CGBitmapContext creation only fails on
            // invalid dimensions or resource exhaustion — the caller-computed
            // sizes are always valid, and the failure is not injectable.
            return nil
        }
        ctx.scaleBy(x: displayScale, y: displayScale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        DisplayListRenderer.draw(list, in: ctx, options: options)

        return FastPNGEncoder.png(from: ctx)
            ?? ctx.makeImage().flatMap(pngData)  // defensive fallback
    }

    /// Render many formulas to PNG concurrently across all cores.
    /// Results preserve input order; failed formulas yield `nil`.
    public static func pngs(
        for formulas: [String],
        style: MathStyle = .display,
        color: SwaTex.Color = .black,
        options: RenderOptions = RenderOptions(),
        displayScale: CGFloat = 2,
        cache: FormulaCache? = nil
    ) async -> [Data?] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (i, latex) in formulas.enumerated() {
                group.addTask {
                    guard
                        let list = try? SwaTexEngine.displayList(
                            for: latex, style: style, color: color, cache: cache)
                    else {
                        return (i, nil)
                    }
                    return (i, png(for: list, options: options, displayScale: displayScale))
                }
            }
            var results = [Data?](repeating: nil, count: formulas.count)
            for await (i, data) in group {
                results[i] = data
            }
            return results
        }
    }
    /// Render a display list into a `CGImage`.
    ///
    /// - Parameter displayScale: pixel density multiplier (e.g. 2 or 3 for
    ///   Retina displays).
    public static func image(
        for list: DisplayList,
        options: RenderOptions = RenderOptions(),
        displayScale: CGFloat = 2
    ) -> CGImage? {
        let m = DisplayListRenderer.metrics(for: list, options: options)
        let pixelWidth = max(Int((m.width * displayScale).rounded(.up)), 1)
        let pixelHeight = max(Int((m.height * displayScale).rounded(.up)), 1)

        guard
            let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            // INTENTIONALLY UNCOVERED: CGBitmapContext creation only fails on
            // invalid dimensions or resource exhaustion — the caller-computed
            // sizes are always valid, and the failure is not injectable.
            return nil
        }

        ctx.scaleBy(x: displayScale, y: displayScale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        DisplayListRenderer.draw(list, in: ctx, options: options)
        return ctx.makeImage()
    }

    /// Render a LaTeX string into a `CGImage`.
    public static func image(
        latex: String,
        style: MathStyle = .display,
        color: SwaTex.Color = .black,
        options: RenderOptions = RenderOptions(),
        displayScale: CGFloat = 2
    ) throws(ParseError) -> CGImage? {
        let list = try SwaTexEngine.displayList(for: latex, style: style, color: color)
        return image(for: list, options: options, displayScale: displayScale)
    }

    /// Encode a `CGImage` as PNG data.
    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else {
            // INTENTIONALLY UNCOVERED: ImageIO only refuses a destination for
            // an unknown UTI or invalid count — both constant here; the
            // failure is not injectable.
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            // INTENTIONALLY UNCOVERED: finalize fails only on I/O or encoder
            // faults ImageIO does not let a test inject.
            return nil
        }
        return data as Data
    }

    /// Render a LaTeX string straight to PNG data (fast-encoder path).
    public static func png(
        latex: String,
        style: MathStyle = .display,
        options: RenderOptions = RenderOptions(),
        displayScale: CGFloat = 2
    ) throws(ParseError) -> Data? {
        let list = try SwaTexEngine.displayList(for: latex, style: style)
        return png(for: list, options: options, displayScale: displayScale)
    }
}
