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

// libz's running CRC-32 (same table polynomial as PNG, RFC 2083 §15) with
// hardware CRC instructions on arm64 — ~80x the byte-at-a-time table loop.
// Seed with 0; libz applies the 0xFFFFFFFF pre/post conditioning itself.
@_silgen_name("crc32")
private func zlibCrc32(
    _ crc: UInt, _ buf: UnsafePointer<UInt8>?, _ len: UInt32
) -> UInt

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

        // 1+2. Un-premultiply alpha (PNG stores straight alpha) directly into
        // the filtered-scanline layout: each PNG row is `0x00 (filter None) +
        // pixels`, so pointing vImage's destination at offset 1 with a row
        // stride of `1 + rowBytes` interleaves the filter bytes for free —
        // no zero-fill and no second full-buffer copy.
        var src = vImage_Buffer(
            data: base, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: bytesPerRow)
        let straightRowBytes = width * 4
        let filteredRowBytes = 1 + straightRowBytes
        var unpremulError: vImage_Error = kvImageNoError
        let raw = [UInt8](unsafeUninitializedCapacity: height * filteredRowBytes) {
            buf, count in
            let p = buf.baseAddress!
            for row in 0..<height {
                p[row * filteredRowBytes] = 0  // filter 0 = None
            }
            var dst = vImage_Buffer(
                data: p + 1, height: vImagePixelCount(height),
                width: vImagePixelCount(width), rowBytes: filteredRowBytes)
            unpremulError = vImageUnpremultiplyData_RGBA8888(
                &src, &dst, vImage_Flags(kvImageNoFlags))
            count = height * filteredRowBytes
        }
        guard unpremulError == kvImageNoError else { return nil }

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
        appendChunk(type: "IDAT", payload: deflated, to: &out)

        appendChunk(type: "IEND", payload: [], to: &out)
        return out
    }

    // MARK: - PNG plumbing

    private static func appendChunk(
        type: String, payload: some Collection<UInt8> & ContiguousBytes, to out: inout Data
    ) {
        appendBigEndian(UInt32(payload.count), to: &out)
        let typeBytes = Array(type.utf8)
        out.append(contentsOf: typeBytes)
        out.append(contentsOf: payload)
        // The chunk CRC covers type + payload; chain the running CRC over
        // both instead of concatenating them into a throwaway buffer.
        var crc = crc32Chained(0, typeBytes)
        crc = crc32Chained(crc, payload)
        appendBigEndian(UInt32(truncatingIfNeeded: crc), to: &out)
    }

    /// Advance a running libz CRC-32. Empty input returns `crc` unchanged —
    /// never forward a nil/empty buffer to libz, whose NULL-buf convention
    /// is "reset to the initial value", which would corrupt the chain
    /// (e.g. IEND's empty payload).
    private static func crc32Chained(_ crc: UInt, _ bytes: some ContiguousBytes) -> UInt {
        bytes.withUnsafeBytes { buf in
            guard let base = buf.baseAddress, !buf.isEmpty else { return crc }
            return zlibCrc32(
                crc, base.assumingMemoryBound(to: UInt8.self), UInt32(buf.count))
        }
    }

    private static func appendBigEndian(_ v: UInt32, to data: inout Data) {
        withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) }
    }
}
