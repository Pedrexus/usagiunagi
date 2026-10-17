import Foundation
import StudyCore
import StudyPersistence

/// Separate-process durability check of the production store, with synthetic data only.
@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, ["write", "read"].contains(args[1]) else {
            print("Usage: NativePersistenceProbe write|read /path/to/disposable/study.store")
            return
        }
        let store = try await StudyStore.open(at: URL(fileURLWithPath: args[2]))
        if args[1] == "write" {
            for id in ["first", "second"] {
                let snapshot = StudySnapshot(accountID: id, username: id, currentLevel: 1,
                    assignments: [], statistics: [], levels: [], subjects: [])
                try await store.saveSnapshot(snapshot, credentialID: id)
            }
            var session = try StudySession(items: [.init(id: 0, subjectID: 42, assignmentID: 142,
                srsStage: 3, hasReading: false)], seed: 1)
            let revision = try await store.saveSession(session, accountID: "first", expectedRevision: nil)
            let question = session.nextQuestion()!
            _ = try session.mark(.correct, for: question, now: 100)
            try await store.saveSession(session, accountID: "first", expectedRevision: revision)
            let review = try await store.pendingReviews(accountID: "first").first!
            try await store.beginReviewAttempt(review)
            try await store.saveMaterial(.init(subjectID: 42, meaningNote: "offline note"), accountID: "first", expectedRevision: nil)
            try await store.saveMaterial(.init(subjectID: 42, meaningNote: "other account"), accountID: "second", expectedRevision: nil)
            print("PASS: production store saved session, pending answer, attempt marker and notes")
        } else {
            let session = try await store.session(accountID: "first")!
            let review = try await store.pendingReviews(accountID: "first").first!
            let first = try await store.materials(accountID: "first").first!
            let second = try await store.materials(accountID: "second").first!
            precondition(session.session.completedIDs == [0])
            precondition(review.attempted && review.submission.createdAt == 100)
            precondition(first.pending && first.material.meaningNote == "offline note")
            precondition(second.pending && second.material.meaningNote == "other account")
            print("PASS: fresh process restored production models, pending work and account isolation")
        }
    }
}
