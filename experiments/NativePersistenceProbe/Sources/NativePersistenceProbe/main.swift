import Foundation
import StudyCore
import StudyPersistence

/// Separate-process durability check of the production store, with synthetic data only.
@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, ["write", "read", "read-attempts", "write-catalog", "read-catalog"].contains(args[1]) else {
            print("Usage: NativePersistenceProbe write|read|read-attempts|write-catalog|read-catalog /path/to/disposable/study.store")
            return
        }
        let store = try await StudyStore.open(at: URL(fileURLWithPath: args[2]))
        if args[1].hasSuffix("catalog") {
            if args[1] == "write-catalog" {
                var profile = StudyAccountProfile(username: "upgrade"); profile.level = 4; profile.maxLevelGranted = 60
                var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
                var subject = CatalogSubject(id: 42, kind: .kanji); subject.level = 4; subject.japanese = "猫"
                subject.meanings = [.init("Cat", role: .primary)]; subject.meaningMnemonic = "Saved mnemonic"
                source.subjects = [subject]
                var assignment = CatalogAssignment(id: 142, subjectID: 42, kind: .kanji); assignment.level = 4; assignment.srsStage = 5
                source.assignments = [assignment]
                source.materials = [.init(serverID: 242, value: .init(subjectID: 42, meaningNote: "pending migration note"), pending: true, legacyRevision: 2)]
                try await store.importLegacyAccount(source, sourceID: "fixture", verifiedAccountID: "upgrade", verifiedUsername: "upgrade", credentialID: "upgrade")
                print("PASS: wrote production catalog, assignment and pending note")
            } else {
                let subject = try await store.catalog(accountID: "upgrade").first!
                let assignment = try await store.assignments(accountID: "upgrade").first!
                let note = try await store.materials(accountID: "upgrade").first!
                precondition(subject.japanese == "猫" && subject.meaningMnemonic == "Saved mnemonic")
                precondition(assignment.id == 142 && assignment.level == 4 && assignment.srsStage == 5)
                precondition(note.pending && note.material.meaningNote == "pending migration note" && note.serverID == 242)
                precondition(note.issue?.reason == .uncertain)
                print("PASS: reopened catalog, assignment and pending note across schema upgrade")
            }
            return
        }
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
            let client = WaniKaniClient { request in
                // Synthetic transport only. No request is sent to WaniKani.
                if request.httpMethod != "GET" { throw URLError(.timedOut) }
                let body = request.url?.path == "/v2/user"
                    ? #"{"object":"user","data":{"id":"first","username":"first","level":1,"current_vacation_started_at":null}}"#
                    : #"{"object":"collection","total_count":0,"pages":{"next_url":null},"data":[]}"#
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do {
                _ = try await store.uploadPending(accountID: "first", token: "synthetic", client: client)
                preconditionFailure("Expected the synthetic material write to time out")
            } catch let error as URLError { precondition(error.code == .timedOut) }
            print("PASS: production store saved session, uncertain review and exact attempted note revision")
        } else {
            let session = try await store.session(accountID: "first")!
            let review = try await store.pendingReviews(accountID: "first").first!
            let first = try await store.materials(accountID: "first").first!
            let second = try await store.materials(accountID: "second").first!
            precondition(session.session.completedIDs == [0])
            precondition(review.attempted && review.submission.createdAt == 100)
            precondition(first.pending && first.material.meaningNote == "offline note")
            precondition(second.pending && second.material.meaningNote == "other account")
            if args[1] == "read-attempts" {
                precondition(review.issue?.reason == .uncertain)
                precondition(first.attemptedRevision == first.revision && first.issue?.reason == .uncertain)
                precondition(first.attemptedMaterial?.meaningNote == "offline note")
                precondition(second.attemptedRevision == nil)
            }
            print("PASS: fresh process restored production models, pending work and account isolation")
        }
    }
}
