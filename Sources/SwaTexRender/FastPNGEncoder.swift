import Accelerate
import CoreGraphics
import Foundation

// libz's stable C ABI (linked via Package.swift `linkedLibrary("z")`).
// `compress2` emits a complete zlib stream (header + deflate + Adler-32)
// at a chosen speed/size level — unlike libcompression's COMPRESSION_ZLIB,
// which is a raw, no-knob, max-compression deflate (measured 2x slower than
// ImageIO end-to-end; see B-006).
@_silgen_name("compress2")
private func zlibCompress2(
    _ dest: UnsafeMutablePointer<UInt8>, _ destLen: UnsafeMutablePointer<UInt>,
    _ source: UnsafePointer<UInt8>, _ sourceLen: UInt, _ level: Int32
) -> Int32

/// Minimal, fast PNG encoder for formula bitmaps.
///
/// ImageIO's `CGImageDestination` is a general-purpose encoder (color
/// profiles, metadata, thumbnails) and dominated the PNG pipeline at ~76 %
/// of per-formula cost (B-006 in the performance log). This encoder writes
/// exactly what a formula bitmap needs — 8-bit RGBA, no ancillary chunks —
/// using OS SIMD primitives:
///
/// - `vImageUnpremultiplyData_RGBA8888` (Accelerate) to convert the
///   CGContext's premultiplied alpha to PNG's straight alpha,
/// - libz `compress2` at level 1 for the zlib stream — PNG viewers don't
///   care about ratio, apps care about latency; level 1 is ~6x faster to
///   encode than max compression for ~25 % larger files.
///
/// Output correctness is verified by round-trip decoding through ImageIO and
/// comparing pixels against the ImageIO-encoded reference (FastPNGTests).
enum FastPNGEncoder {
    /// Encode a rendered bitmap context (premultiplied RGBA8, sRGB) as PNG.
    ///
    /// Reads the context's backing store directly — no intermediate
    /// `CGImage`/`makeImage()` copy.
    static func png(from ctx: CGContext) -> Data? {
        guard let base = ctx.data else { return nil }
        let width = ctx.width
        let height = ctx.height
        let bytesPerRow = ctx.bytesPerRow
        guard width > 0, height > 0 else { return nil }

        // 1. Un-premultiply alpha (PNG stores straight alpha). SIMD via vImage.
        var src = vImage_Buffer(
            data: base, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: bytesPerRow)
        let straightRowBytes = width * 4
        var straight = [UInt8](repeating: 0, count: straightRowBytes * height)
        let unpremulError = straight.withUnsafeMutableBytes { buf -> vImage_Error in
            var dst = vImage_Buffer(
                data: buf.baseAddress, height: vImagePixelCount(height),
                width: vImagePixelCount(width), rowBytes: straightRowBytes)
            return vImageUnpremultiplyData_RGBA8888(&src, &dst, vImage_Flags(kvImageNoFlags))
        }
        guard unpremulError == kvImageNoError else { return nil }

        // 2. Add PNG row filter bytes (filter 0 = None per scanline).
        var raw = [UInt8]()
        raw.reserveCapacity(height * (1 + straightRowBytes))
        straight.withUnsafeBytes { buf in
            let p = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                raw.append(0)
                raw.append(
                    contentsOf: UnsafeBufferPointer(
                        start: p + row * straightRowBytes, count: straightRowBytes))
            }
        }

        // 3. zlib stream via libz at level 1 (speed over ratio).
        let dstCapacity = raw.count + raw.count / 1000 + 64  // > compressBound
        var deflatedLen = UInt(dstCapacity)
        let deflated = [UInt8](unsafeUninitializedCapacity: dstCapacity) { buf, count in
            let status = raw.withUnsafeBufferPointer { rawBuf in
                zlibCompress2(
                    buf.baseAddress!, &deflatedLen,
                    rawBuf.baseAddress!, UInt(rawBuf.count), 1)
            }
            count = status == 0 ? Int(deflatedLen) : 0
        }
        guard !deflated.isEmpty else { return nil }

        // 4. Assemble: signature, IHDR, IDAT (zlib wrapper), IEND.
        var out = Data(capacity: deflated.count + 128)
        out.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])  // 8-bit, RGBA, deflate, none, none
        appendChunk(type: "IHDR", payload: ihdr, to: &out)

        // compress2 output is a complete zlib stream (header + Adler-32).
        appendChunk(type: "IDAT", payload: Data(deflated), to: &out)

        appendChunk(type: "IEND", payload: Data(), to: &out)
        return out
    }

    // MARK: - PNG plumbing

    private static func appendChunk(type: String, payload: Data, to out: inout Data) {
        appendBigEndian(UInt32(payload.count), to: &out)
        var body = Data(type.utf8)
        body.append(payload)
        out.append(body)
        appendBigEndian(crc32(body), to: &out)
    }

    private static func appendBigEndian(_ v: UInt32, to data: inout Data) {
        withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) }
    }

    /// CRC-32 (ISO 3309), table-driven.
    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }
}
