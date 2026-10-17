import Foundation
import Testing
@testable import StudyCore

private actor APIStub {
    struct Reply: Sendable { var status = 200; var body: String; var headers: [String: String] = [:] }
    var requests: [URLRequest] = []
    var replies: [Reply]
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        let reply = replies.removeFirst()
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status,
            httpVersion: nil, headerFields: reply.headers)!)
    }
    var client: WaniKaniClient { WaniKaniClient { try await self.send($0) } }
}

private let assignmentJSON = #"{"id":142,"object":"assignment","data":{"subject_id":42,"subject_type":"kana_vocabulary","level":12,"srs_stage":2,"available_at":"2026-10-18T00:00:00Z","started_at":"2026-10-01T00:00:00Z","unlocked_at":"2026-09-30T00:00:00Z","passed_at":null,"burned_at":null,"resurrected_at":null,"hidden":false}}"#
private let reviewJSON = #"{"id":0,"object":"review","data":{"assignment_id":142,"subject_id":42,"incorrect_meaning_answers":2,"incorrect_reading_answers":0,"ending_srs_stage":2},"resources_updated":{"assignment":ASSIGNMENT}}"#.replacingOccurrences(of: "ASSIGNMENT", with: assignmentJSON)
private let materialJSON = #"{"id":242,"object":"study_material","data":{"subject_id":42,"meaning_note":"note","reading_note":"ねこ","meaning_synonyms":["kitty"]}}"#
private func collection(_ rows: String) -> String { #"{"pages":{"next_url":null},"data":[ROWS]}"#.replacingOccurrences(of: "ROWS", with: rows) }
private func answer(lesson: Bool = false, createdAt: Int64? = 100) -> StudyReviewSubmission {
    .init(itemID: 0, subjectID: 42, assignmentID: 142, isLesson: lesson, meaningWrong: true,
        readingWrong: false, meaningWrongCount: 2, readingWrongCount: 0, createdAt: createdAt)
}
private func body(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

struct NativeClientTests {
    @MainActor @Test func responseDecodingLeavesTheUIThread() async throws {
        struct Probe: Decodable, Sendable {
            let decodedOnMainThread: Bool
            init(from decoder: any Decoder) throws {
                // A synchronous decoder models the expensive part of a large account download.
                _ = try decoder.container(keyedBy: CodingKeys.self)
                decodedOnMainThread = Thread.isMainThread
            }
            private enum CodingKeys: String, CodingKey { case value }
        }
        let client = WaniKaniClient { request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }
        let result: Probe = try await client.request(URL(string: "https://api.wanikani.com/v2/user")!, token: "fixture")
        #expect(!result.decodedOnMainThread)
    }

    @Test func reviewUsesNativeJSONAndAcceptsTheDocumentedZeroReceiptID() async throws {
        let stub = APIStub([.init(body: reviewJSON)])
        let client = await stub.client
        let result = try await client.submit(answer(), token: "fixture-token", now: Date(timeIntervalSince1970: 2000))
        #expect(result.id == 142 && result.subjectID == 42 && result.isKanaOnlyVocabulary && result.hidden == false)
        let requests = await stub.requests, request = try #require(requests.first)
        #expect(requests.count == 1 && request.httpMethod == "POST" && request.url?.path == "/v2/reviews")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(request.value(forHTTPHeaderField: "Wanikani-Revision") == "20170710")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        let review = try #require(body(request)["review"] as? [String: Any])
        #expect(review["assignment_id"] as? Int == 142 && review["incorrect_meaning_answers"] as? Int == 2)
        #expect(review["incorrect_reading_answers"] as? Int == 0 && review["created_at"] as? String == "1970-01-01T00:01:40Z")
    }

    @Test func recentReviewOmitsTimestampButOfflineLessonUsesNestedAssignmentBody() async throws {
        let stub = APIStub([.init(body: reviewJSON), .init(body: assignmentJSON)])
        let client = await stub.client
        _ = try await client.submit(answer(createdAt: 1999), token: "token", now: Date(timeIntervalSince1970: 2000))
        _ = try await client.submit(answer(lesson: true), token: "token")
        let requests = await stub.requests
        let review = try #require(body(requests[0])["review"] as? [String: Any])
        #expect(review["created_at"] == nil)
        let lesson = try #require(body(requests[1])["assignment"] as? [String: Any])
        #expect(lesson["started_at"] as? String == "1970-01-01T00:01:40Z")
        #expect(requests[1].httpMethod == "PUT" && requests[1].url?.path == "/v2/assignments/142/start")
    }

    @Test func assignmentLookupChecksSubjectIdentityAndPreservesServerState() async throws {
        let stub = APIStub([.init(body: collection(assignmentJSON))])
        let result = try #require(await stub.client.assignment(subjectID: 42, token: "token"))
        #expect(result.unlockedAt != nil && result.startedAt != nil && result.availableAt != nil && result.resurrectedAt == nil)
        #expect(await stub.requests.first?.url?.query == "subject_ids=42")
        for rows in [assignmentJSON.replacingOccurrences(of: "\"subject_id\":42", with: "\"subject_id\":43"), assignmentJSON + "," + assignmentJSON, assignmentJSON.replacingOccurrences(of: "kana_vocabulary", with: "unknown_subject")] {
            let invalid = APIStub([.init(body: collection(rows))])
            await #expect(throws: WaniKaniClient.APIError.self) { try await invalid.client.assignment(subjectID: 42, token: "token") }
        }
        let absent = APIStub([.init(body: collection(""))])
        #expect(try await absent.client.assignment(subjectID: 42, token: "token") == nil)
    }

    @Test func createAndUpdateNotesUseFreshSubjectLookup() async throws {
        let value = StudyMaterial(subjectID: 42, meaningNote: "note", readingNote: "ねこ", meaningSynonyms: ["kitty"])
        for existing in [false, true] {
            let stub = APIStub([.init(body: collection(existing ? materialJSON : "")), .init(body: materialJSON)])
            let result = try await stub.client.saveMaterial(value, token: "token")
            #expect(result.id == 242 && result.value == value)
            let requests = await stub.requests
            #expect(requests.count == 2 && requests[0].httpMethod == "GET" && requests[0].url?.query == "subject_ids=42")
            #expect(requests[1].httpMethod == (existing ? "PUT" : "POST"))
            #expect(requests[1].url?.path == (existing ? "/v2/study_materials/242" : "/v2/study_materials"))
            let note = try #require(body(requests[1])["study_material"] as? [String: Any])
            #expect(note["subject_id"] as? Int == (existing ? nil : 42))
            #expect(note["meaning_synonyms"] as? [String] == ["kitty"])
        }
    }

    @Test func malformedOrMismatchedSuccessNeverAcknowledgesAReview() async {
        let invalid = ["{}", reviewJSON.replacingOccurrences(of: "\"subject_id\":42", with: "\"subject_id\":99"),
            reviewJSON.replacingOccurrences(of: "\"incorrect_meaning_answers\":2", with: "\"incorrect_meaning_answers\":0"),
            reviewJSON.replacingOccurrences(of: "\"ending_srs_stage\":2", with: "\"ending_srs_stage\":8")]
        for response in invalid {
            let stub = APIStub([.init(body: response)])
            await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.submit(answer(), token: "token") }
            #expect(await stub.requests.count == 1)
        }
    }

    @Test func writesAreNotAutomaticallyRetriedForErrorsOrTimeouts() async {
        for status in [401, 403, 409, 422, 429, 500, 503] {
            let stub = APIStub([.init(status: status, body: "{}", headers: ["Retry-After": "120"])])
            await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.submit(answer(), token: "token") }
            #expect(await stub.requests.count == 1)
        }
        let timedOut = APIStub([])
        await #expect(throws: URLError.self) { try await timedOut.client.submit(answer(), token: "token") }
        #expect(await timedOut.requests.count == 1)
    }

    @Test func rateLimitHeadersAreNotShortenedAndSupportHTTPDates() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let response = HTTPURLResponse(url: URL(string: "https://api.wanikani.com/v2/user")!, statusCode: 429,
            httpVersion: nil, headerFields: ["Retry-After": "60", "RateLimit-Reset": "1120"])!
        #expect(WaniKaniClient.retryDate(response, now: now, fallback: 2) == Date(timeIntervalSince1970: 1120))
        let dateResponse = HTTPURLResponse(url: response.url!, statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "Thu, 01 Jan 1970 00:20:00 GMT"])!
        #expect(WaniKaniClient.retryDate(dateResponse, now: now, fallback: 2) == Date(timeIntervalSince1970: 1200))
        let stub = APIStub([.init(status: 429, body: "{}", headers: ["Retry-After": "120"])])
        await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.account(token: "token") }
        #expect(await stub.requests.count == 1)
    }

    @Test func invalidPayloadAndCancellationDoNotSendRequests() async {
        let stub = APIStub([]), invalid = StudyReviewSubmission(itemID: 0, subjectID: 42, assignmentID: 0,
            isLesson: false, meaningWrong: false, readingWrong: false, meaningWrongCount: 0, readingWrongCount: 0, createdAt: nil)
        await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.submit(invalid, token: "token") }
        let client = await stub.client
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.submit(answer(), token: "token")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await stub.requests.isEmpty)
    }

    @Test func wrongMaterialIdentityOrContentIsRejected() async {
        let value = StudyMaterial(subjectID: 42, meaningNote: "note", readingNote: "ねこ", meaningSynonyms: ["kitty"])
        for response in ["{}", materialJSON.replacingOccurrences(of: "\"id\":242", with: "\"id\":243"),
            materialJSON.replacingOccurrences(of: "\"note\"", with: "\"lost edit\"")] {
            let stub = APIStub([.init(body: collection(materialJSON)), .init(body: response)])
            await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.saveMaterial(value, token: "token") }
            #expect(await stub.requests.count == 2)
        }
    }

    @Test func cancellationAfterTransportAndUnstartedLessonCannotReportSuccess() async {
        let client = WaniKaniClient { request in
            withUnsafeCurrentTask { $0?.cancel() }
            return (Data(reviewJSON.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let task = Task { try await client.submit(answer(), token: "token") }
        await #expect(throws: CancellationError.self) { try await task.value }
        let stub = APIStub([.init(body: assignmentJSON.replacingOccurrences(of: "\"started_at\":\"2026-10-01T00:00:00Z\"", with: "\"started_at\":null"))])
        await #expect(throws: WaniKaniClient.APIError.self) { try await stub.client.submit(answer(lesson: true), token: "token") }
    }
}
