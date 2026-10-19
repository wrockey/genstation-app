import Foundation

/// Pure concurrency-cap arithmetic — no dependencies.
public struct JobSchedulerCore {
    public var maxConcurrent: Int

    public init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    public func slotsAvailable(running: Int) -> Int {
        max(0, maxConcurrent - running)
    }

    /// Which queued job IDs may start now, preserving FIFO order.
    public func idsToStart(queued: [UUID], runningCount: Int) -> [UUID] {
        Array(queued.prefix(slotsAvailable(running: runningCount)))
    }
}
