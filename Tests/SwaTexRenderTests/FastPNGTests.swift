import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwaTex
@testable import SwaTexRender

/// Correctness of the fast PNG encoder: output must decode to pixels
/// identical to the ImageIO reference encoder's.
@Suite("FastPNG")
struct FastPNGTests {
    private func decodeRGBA(_ png: Data) throws -> (pixels: [UInt8], w: Int, h: Int) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let w = image.width
        let h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(
            CGContext(
                data: &pixels, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (pixels, w, h)
    }

    @Test(arguments: [
        #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
        #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#,
        #"\textcolor{red}{x} + \textcolor{#00ff0080}{y}"#,  // semi-transparent ink
        #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
    ])
    func matchesImageIOReference(_ latex: String) throws {
        let list = try SwaTexEngine.displayList(for: latex)

        // Fast path.
        let fast = try #require(ImageRenderer.png(for: list))
        // Reference path (ImageIO on the identical rendering).
        let image = try #require(ImageRenderer.image(for: list))
        let reference = try #require(ImageRenderer.pngData(image))

        let a = try decodeRGBA(fast)
        let b = try decodeRGBA(reference)
        #expect(a.w == b.w)
        #expect(a.h == b.h)
        #expect(a.pixels == b.pixels, "decoded pixels must be identical")
    }

    @Test func opaqueBackground() throws {
        let list = try SwaTexEngine.displayList(for: #"x^2"#)
        let opts = RenderOptions(fontSize: 40, backgroundColor: .white)
        let fast = try #require(ImageRenderer.png(for: list, options: opts))
        let decoded = try decodeRGBA(fast)
        // Corner pixel must be opaque white.
        #expect(decoded.pixels[0] == 255)
        #expect(decoded.pixels[3] == 255)
    }

    @Test func pngSignatureAndStructure() throws {
        let png = try #require(try ImageRenderer.png(latex: #"a+b"#))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // IHDR immediately follows the signature.
        #expect(String(decoding: png[12..<16], as: UTF8.self) == "IHDR")
        #expect(String(decoding: png.suffix(8).prefix(4), as: UTF8.self) == "IEND")
    }

    @Test func parallelBatchAPI() async throws {
        let results = await ImageRenderer.pngs(for: [#"x"#, #"\frac{1}"#, #"y^2"#])
        #expect(results.count == 3)
        #expect(results[0] != nil)
        #expect(results[1] == nil)  // parse error → nil, doesn't fail batch
        #expect(results[2] != nil)
    }
}
