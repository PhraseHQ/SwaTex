import Foundation
import Synchronization

/// Type-erased carrier across the pthread C boundary (a C-convention entry
/// point cannot reference generic context, so the closure is pre-erased).
private final class ThreadRunBox {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

/// Run `body` on a dedicated pthread with an exact stack size and block
/// until it finishes. `pthread_join` is the synchronization — no semaphores.
///
/// The stack-guard tests need threads both far smaller (64 KB) and far
/// larger (64 MB) than anything Foundation/Swift Concurrency provide:
/// probe-governed degradation must trigger on the former and must NOT
/// trigger on the latter, in both debug and release frame sizes.
func runOnThread<T: Sendable>(
    stackSize: Int, _ body: @escaping @Sendable () -> T
) -> T {
    let slot = Mutex<T?>(nil)
    let box = ThreadRunBox { slot.withLock { $0 = body() } }
    let ctx = Unmanaged.passRetained(box).toOpaque()

    var attr = pthread_attr_t()
    pthread_attr_init(&attr)
    pthread_attr_setstacksize(&attr, stackSize)
    var tid: pthread_t?
    let rc = pthread_create(
        &tid, &attr,
        { p in
            Unmanaged<ThreadRunBox>.fromOpaque(p).takeRetainedValue().run()
            return nil
        }, ctx)
    pthread_attr_destroy(&attr)
    precondition(rc == 0, "pthread_create failed: \(rc)")
    pthread_join(tid!, nil)
    return slot.withLock { $0! }
}
