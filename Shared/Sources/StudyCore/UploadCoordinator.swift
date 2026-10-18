import Foundation
import Synchronization

public struct PendingUploadKey: Hashable, Sendable {
    public enum Kind: Sendable { case progress, studyMaterial }
    public let kind: Kind
    public let subjectID: Int64
    public init(kind: Kind, subjectID: Int64) {
        self.kind = kind; self.subjectID = subjectID
    }
}

/// A synchronous lifetime fence for database reset/logout, including callbacks already in flight.
public final class UploadLifetime: Sendable {
    private let active = Mutex(true)
    public init() {}
    public func invalidate() { active.withLock { $0 = false } }
    public func check() throws { try withActive {} }
    public func withActive<T>(_ operation: () throws -> T) throws -> T {
        try active.withLock { active in
            guard active else { throw CancellationError() }
            return try operation()
        }
    }
}

/// Payloads remain in the host's durable store. Acknowledgement must compare the exact sent bytes.
public struct UploadRepository: Sendable {
    public let lifetime: UploadLifetime
    let load: @Sendable (PendingUploadKey) async throws -> Data?
    let send: @Sendable (PendingUploadKey, Data) async throws -> Void
    let acknowledge: @Sendable (PendingUploadKey, Data) async throws -> Void

    public init(lifetime: UploadLifetime,
                load: @escaping @Sendable (PendingUploadKey) async throws -> Data?,
                send: @escaping @Sendable (PendingUploadKey, Data) async throws -> Void,
                acknowledge: @escaping @Sendable (PendingUploadKey, Data) async throws -> Void) {
        self.lifetime = lifetime; self.load = load; self.send = send
        self.acknowledge = acknowledge
    }
}

/// One upload lane shared by immediate saves and background sync, across both resource kinds.
/// Each turn reloads its payload after waiting, so queued snapshots cannot overwrite newer edits.
public actor UploadCoordinator {
    private var tail: Task<Void, Never>?
    private var lastJob: UUID?
    public init() {}

    public func enqueue(_ keys: [PendingUploadKey], repository: UploadRepository) -> Task<Void, any Error> {
        let predecessor = tail
        let id = UUID()
        let job = Task {
            defer { if lastJob == id { tail = nil; lastJob = nil } }
            await predecessor?.value
            for key in keys {
                try repository.lifetime.check()
                guard let payload = try await repository.load(key) else { continue }
                try repository.lifetime.check()
                try await repository.send(key, payload)
                try repository.lifetime.check()
                try await repository.acknowledge(key, payload)
            }
        }
        lastJob = id
        // Failure reaches this caller but never poisons later independently queued work.
        tail = Task { _ = await job.result }
        return job
    }
}
