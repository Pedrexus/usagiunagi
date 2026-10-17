import Foundation
import SwiftData

@Model final class PendingAnswer {
    #Unique<PendingAnswer>([\.account, \.subjectID])
    var account: String
    var subjectID: Int64
    var revision: UUID
    var answer: Data
    var attempted: Bool
    init(account: String, subjectID: Int64, answer: Data) {
        self.account = account; self.subjectID = subjectID; self.answer = answer
        revision = UUID(); attempted = false
    }
}

@Model final class SessionCheckpoint {
    @Attribute(.unique) var account: String
    var state: Data
    init(account: String, state: Data) { self.account = account; self.state = state }
}

@ModelActor actor LocalStudyStore {
    struct Pending: Sendable { let revision: UUID; let data: Data; let attempted: Bool }
    enum ProbeError: Error { case simulatedFailure }
    func answer(account: String, subjectID: Int64) throws -> Pending? {
        let row = try modelContext.fetch(FetchDescriptor<PendingAnswer>(predicate:
            #Predicate { $0.account == account && $0.subjectID == subjectID })).first
        return row.map { Pending(revision: $0.revision, data: $0.answer, attempted: $0.attempted) }
    }
    func session(account: String) throws -> Data? {
        try modelContext.fetch(FetchDescriptor<SessionCheckpoint>(predicate:
            #Predicate { $0.account == account })).first?.state
    }
    func save(account: String, subjectID: Int64, answer: Data, session: Data, fail: Bool = false) throws {
        modelContext.autosaveEnabled = false
        do {
            try modelContext.transaction {
                let rows = try modelContext.fetch(FetchDescriptor<PendingAnswer>(predicate:
                    #Predicate { $0.account == account && $0.subjectID == subjectID }))
                if let row = rows.first {
                    row.answer = answer; row.revision = UUID(); row.attempted = false
                } else { modelContext.insert(PendingAnswer(account: account, subjectID: subjectID, answer: answer)) }
                if fail { throw ProbeError.simulatedFailure }
                let checkpoints = try modelContext.fetch(FetchDescriptor<SessionCheckpoint>(predicate:
                    #Predicate { $0.account == account }))
                if let row = checkpoints.first { row.state = session }
                else { modelContext.insert(SessionCheckpoint(account: account, state: session)) }
            }
        } catch { modelContext.rollback(); throw error }
    }
    func beginAttempt(account: String, subjectID: Int64, revision: UUID) throws {
        try modelContext.transaction {
            let rows = try modelContext.fetch(FetchDescriptor<PendingAnswer>(predicate:
                #Predicate { $0.account == account && $0.subjectID == subjectID && $0.revision == revision }))
            rows.first?.attempted = true
        }
    }
    func acknowledge(account: String, subjectID: Int64, revision: UUID) throws {
        try modelContext.transaction {
            let rows = try modelContext.fetch(FetchDescriptor<PendingAnswer>(predicate:
                #Predicate { $0.account == account && $0.subjectID == subjectID && $0.revision == revision }))
            for row in rows { modelContext.delete(row) }
        }
    }
}

@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[2])
        let schema = Schema([PendingAnswer.self, SessionCheckpoint.self])
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let store = LocalStudyStore(modelContainer: container)
        func bytes(_ value: String) -> Data { Data(value.utf8) }
        if args[1] == "write" {
            try await store.save(account: "first", subjectID: 42, answer: bytes("old"), session: bytes("step 1"))
            let old = try await store.answer(account: "first", subjectID: 42)!
            try await store.save(account: "first", subjectID: 42, answer: bytes("new"), session: bytes("step 2"))
            try await store.acknowledge(account: "first", subjectID: 42, revision: old.revision)
            let current = try await store.answer(account: "first", subjectID: 42)!
            precondition(current.data == bytes("new"), "Old acknowledgement removed newer work")
            try await store.beginAttempt(account: "first", subjectID: 42, revision: current.revision)
            try await store.save(account: "second", subjectID: 42, answer: bytes("other account"), session: bytes("other step"))
            do {
                try await store.save(account: "first", subjectID: 42, answer: bytes("must roll back"), session: bytes("bad step"), fail: true)
                fatalError("Expected injected failure")
            } catch LocalStudyStore.ProbeError.simulatedFailure {}
            let rolledBack = try await store.answer(account: "first", subjectID: 42)!
            precondition(rolledBack.data == bytes("new") && rolledBack.attempted)
            print("PASS: atomic session + answer, revised acknowledgement, account separation, rollback")
        } else {
            let first = try await store.answer(account: "first", subjectID: 42)!
            let second = try await store.answer(account: "second", subjectID: 42)!
            let session = try await store.session(account: "first")
            precondition(first.data == bytes("new") && first.attempted, "Uncertain attempt lost across restart")
            precondition(second.data == bytes("other account") && !second.attempted)
            precondition(session == bytes("step 2"), "Session and answer diverged")
            print("PASS: separate-process reopen retains answers, session, attempt state and account isolation")
        }
    }
}
