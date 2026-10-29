import XCTest
@testable import v2s

/// Lock-guarded counter so concurrent test tasks can observe overlap
/// without relying on captured-var mutation.
private final class ConcurrencyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var maximum = 0

    func enter() {
        lock.lock()
        current += 1
        maximum = max(maximum, current)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        current -= 1
        lock.unlock()
    }

    var currentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

final class WhisperTranscriptionGateTests: XCTestCase {
    func testConcurrentRunsNeverOverlap() async throws {
        let gate = WhisperTranscriptionGate()
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try? await gate.run {
                        counter.enter()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        counter.leave()
                    }
                }
            }
        }

        XCTAssertEqual(counter.maximum, 1)
        XCTAssertEqual(counter.currentCount, 0)
    }

    func testCancelledWaiterLeavesTheQueueUsable() async throws {
        let gate = WhisperTranscriptionGate()

        // Hold the gate while a second caller queues behind it. The settle
        // sleep runs after the holder task was created, so the holder has
        // acquired the uncontended gate before the waiter starts.
        let holder = Task {
            try await gate.run {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let waiter = Task {
            try await gate.run {
                // Must never run: this waiter is cancelled below.
                XCTFail("Cancelled waiter ran")
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()
        _ = await waiter.result

        try await holder.value

        // The gate must still serve the next caller after a cancellation.
        let served = try await gate.run { "ok" }
        XCTAssertEqual(served, "ok")
    }
}
