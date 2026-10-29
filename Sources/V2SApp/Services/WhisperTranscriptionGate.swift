import Foundation

/// Serializes access to one shared WhisperKit pipeline.
///
/// WhisperKit keeps mutable state between calls (e.g. current timings), so
/// two sessions must not drive the same instance concurrently. The gate
/// hands the pipeline to one transcription at a time; a caller cancelled
/// while waiting leaves the queue instead of deadlocking it.
actor WhisperTranscriptionGate {
    private var isLocked = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    func run<T>(_ work: @escaping () async throws -> T) async throws -> T {
        try await acquire()
        defer { Task { await self.release() } }
        return try await work()
    }

    private func acquire() async throws {
        if isLocked == false {
            isLocked = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }
}
