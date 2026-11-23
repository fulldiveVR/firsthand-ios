import Synchronization

/// Allows one analysis pass at a time in a process: the background task, the first scan,
/// or "Find moments now". A second caller gets `false` and does not wait.
public final class AnalysisRunLock: Sendable {
    private let running = Mutex(false)

    public init() {}

    public var isRunning: Bool { running.withLock { $0 } }

    /// Returns `true` if the caller now owns the run. Call `release()` when done.
    public func tryAcquire() -> Bool {
        running.withLock { value in
            guard !value else { return false }
            value = true
            return true
        }
    }

    public func release() {
        running.withLock { $0 = false }
    }
}
