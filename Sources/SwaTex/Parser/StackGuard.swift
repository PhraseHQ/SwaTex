/// Stack headroom probing for the parser's recursion guard (see
/// `Parser.parseExpression`).
///
/// A fixed recursion *count* cannot protect every thread: Swift Concurrency
/// cooperative threads and test workers run on 512 KB stacks, where the
/// depth that fits is an order of magnitude smaller than on the 8 MB main
/// thread — and smaller still in debug builds with their larger frames.
/// Measured on arm64 release: parse overflows a 512 KB thread at ~350
/// nesting levels, well inside the 512-level count guard. Probing the
/// actual remaining stack is exact on every thread and build configuration.

#if canImport(Darwin)
    import Darwin

    /// The address below which the current thread's stack pointer must not
    /// go while keeping `headroom` bytes free. Computed ONCE per `Parser`
    /// (init runs on the thread that parses); the per-recursion check is
    /// then a single local-address comparison — the pthread lookups cost
    /// ~2 % of whole-engine time when performed per level.
    func stackFloorAddress(headroom: Int) -> UInt {
        let thread = pthread_self()
        // Stack base is the HIGH address; the stack grows downward.
        let base = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        return base &- size &+ UInt(headroom)
    }
#else
    /// Non-Darwin fallback: unknown — 0 disables the address check and the
    /// recursion-count guard stands alone.
    func stackFloorAddress(headroom: Int) -> UInt {
        0
    }
#endif

/// True when the current stack pointer is still above `floor`.
@inline(__always)
func stackHasHeadroom(above floor: UInt) -> Bool {
    var probe: UInt8 = 0
    return withUnsafePointer(to: &probe) { UInt(bitPattern: $0) > floor }
}

/// Minimum stack headroom required to *enter* another parse level.
///
/// Calibration (arm64): parse frames ≈1.5 KB/level release, ~6 KB debug;
/// the layout walk over the admitted tree needs comparable space starting
/// from the pipeline entry (measured safe at 300 levels on a 512 KB
/// thread). 96 KB admits ~275 release levels on a 512 KB thread (layout
/// then fits with margin) while leaving realistic debug-build headroom for
/// legitimate ~30-60-level formulas above the test framework's own stack
/// use. Raising this hardens margins but starts rejecting legitimate
/// nesting on small debug-build threads.
let minimumParseStackHeadroom = 96 * 1024

/// Minimum stack headroom required to *enter* another layout/emission level.
///
/// Smaller than the parse reserve on purpose: layout frames are much larger
/// (≈16 KB/level debug, ≈1.4 KB release), so a 96 KB reserve would reject
/// legitimate ~30-level formulas on 512 KB debug threads that the walk
/// actually fits. 32 KB covers the worst single inter-probe chain while
/// leaving release-build capacity at ~350 levels on a 512 KB thread.
let minimumLayoutStackHeadroom = 32 * 1024
