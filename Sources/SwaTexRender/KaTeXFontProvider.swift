import CoreText
import Foundation
import SwaTex
import Synchronization

// CTFont is documented thread-safe (Core Text Programming Guide: "All
// individual functions in Core Text are thread-safe. Font objects (CTFont,
// CTFontDescriptor, and associated objects) can be used simultaneously by
// multiple operations, work queues, or threads."), but Apple hasn't annotated
// it Sendable yet — the same stdlib-gap situation as Regex in the core target.
extension CTFont: @unchecked @retroactive Sendable {}

/// Loads and caches the bundled KaTeX fonts as `CTFont` instances.
///
/// Fonts are created from the TTF data bundled with this target (no global
/// `CTFontManager` registration, so host apps are never polluted). Fonts are
/// cached at unit size (1pt) and scaled per draw call.
public final class KaTeXFontProvider: Sendable {
    public static let shared = KaTeXFontProvider()

    /// Unit-size font cache. `Mutex` from Synchronization gives cheap,
    /// Sendable-checked exclusive access.
    private let cache = Mutex<[FontId: CTFont]>([:])

    /// Sized-font cache keyed by (font, exact size bits). Creating a CTFont
    /// per glyph draw (`CTFontCreateCopyWithAttributes`) dominated the native
    /// render profile — see P-011 in the performance log.
    private struct SizedKey: Hashable {
        var font: FontId
        var sizeBits: UInt64
    }
    private let sizedCache = Mutex<[SizedKey: CTFont]>([:])

    /// Glyph-ID cache: (font, scalar) → CGGlyph. Glyph IDs are
    /// size-independent, so one lookup serves every size. `nil` value is
    /// encoded by absence; unmapped scalars store `0` (.notdef) to also
    /// cache misses.
    private struct GlyphKey: Hashable {
        var font: FontId
        var scalar: UInt32
    }
    private let glyphCache = Mutex<[GlyphKey: CGGlyph]>([:])

    private init() {}

    /// The bundled TTF filename for a KaTeX font.
    private static func resourceName(for fontId: FontId) -> String? {
        switch fontId {
        case .cjkRegular, .cjkFallback, .emojiFallback:
            nil  // resolved via system fonts
        default:
            "KaTeX_\(fontId.rawValue)"
        }
    }

    /// A `CTFont` for the given KaTeX font at the given point size.
    ///
    /// CJK/emoji fallback fonts resolve to system fonts. Unknown/missing fonts
    /// fall back to Main-Regular, matching the Rust renderers.
    public func font(for fontId: FontId, size: CGFloat) -> CTFont {
        // UInt64(_:) widens on watchOS, where CGFloat.native is the 32-bit
        // Float and bitPattern is UInt32; identity elsewhere.
        let key = SizedKey(font: fontId, sizeBits: UInt64(size.native.bitPattern))
        let cached = sizedCache.withLock { $0[key] }
        if let cached {
            return cached
        }

        let unitFont = cache.withLock { cache -> CTFont in
            if let cached = cache[fontId] {
                return cached
            }
            let created = Self.makeUnitFont(fontId)
            cache[fontId] = created
            return created
        }
        let sized = CTFontCreateCopyWithAttributes(unitFont, size, nil, nil)

        sizedCache.withLock { cache in
            // Continuous size changes (pinch zoom, sliders) could grow this
            // without bound; a full reset is cheap to rebuild.
            if cache.count >= 256 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = sized
        }
        return sized
    }

    /// The glyph for `scalar` in a bundled KaTeX font, from the glyph-ID
    /// cache. Returns 0 (.notdef) when the font has no mapping — callers
    /// fall back to system-font resolution.
    func cachedGlyph(for fontId: FontId, scalar: Unicode.Scalar, in font: CTFont) -> CGGlyph {
        let key = GlyphKey(font: fontId, scalar: scalar.value)
        let cached = glyphCache.withLock { $0[key] }
        if let cached {
            return cached
        }

        var utf16 = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let found = CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count)
        let glyph = found ? (glyphs.first ?? 0) : 0

        glyphCache.withLock { $0[key] = glyph }
        return glyph
    }

    /// The TTF for a KaTeX face, looked up in the HOST bundle before this target's own
    /// resource bundle.
    ///
    /// `Bundle.module` resolves to `Bundle.main.bundleURL/SwaTex_SwaTexRender.bundle`. For
    /// a command-line binary that is the directory holding the executable and it is
    /// correct, but for a `.app` `bundleURL` is the app itself, so the path lands at the
    /// bundle ROOT beside `Contents/` - the one place a macOS app may not put anything.
    /// Measured with `codesign` on a Developer ID signature:
    ///
    /// | placement                     | signs                                    |
    /// |-------------------------------|------------------------------------------|
    /// | app root (real dir or symlink)| "unsealed contents present in bundle root"|
    /// | `Contents/MacOS/*.bundle`     | "bundle format unrecognized"             |
    /// | `Contents/Resources/`         | valid, but `Bundle.module` never looks    |
    ///
    /// So an app embedding this package has no placement that is both signable and
    /// findable, and the generated `Bundle.module` accessor calls `fatalError` when both
    /// of its candidates miss. The failure hides on the build machine, where the absolute
    /// `.build` path compiled into the binary still resolves, and arrives as a crash on
    /// the first equation everywhere else.
    ///
    /// Checking `Bundle.main` first gives the host a placement it can sign: copy the faces
    /// into `Contents/Resources/Fonts`. Nothing changes for a SwiftPM executable or a test
    /// run, where `Bundle.main` has no `Fonts` directory and the module bundle answers as
    /// before.
    private static func fontURL(named name: String) -> URL? {
        hostFontURL(named: name)
            ?? Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
    }

    /// The host-bundle half of `fontURL(named:)`, separated so a test can name the bundle.
    /// It must stay free of `Bundle.module`, which traps rather than returning nil.
    static func hostFontURL(named name: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
    }

    private static func makeUnitFont(_ fontId: FontId) -> CTFont {
        if let name = resourceName(for: fontId),
            let url = fontURL(named: name),
            let data = try? Data(contentsOf: url),
            let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
        {
            return CTFontCreateWithFontDescriptor(descriptor, 1, nil)
        }
        // CJK / emoji / missing bundled font → system font (glyph-level
        // fallback happens in the renderer via CTFontCreateForString).
        return CTFontCreateUIFontForLanguage(.system, 1, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 1, nil)
    }
}
