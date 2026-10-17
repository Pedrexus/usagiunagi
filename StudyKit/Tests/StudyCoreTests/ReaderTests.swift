import Foundation
import Testing
@testable import StudyCore

private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, HTTPURLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
private let emptyPage = #"{"pages":{"next_url":null},"data":[]}"#
private let user = #"{"data":{"username":"test","level":12,"vacation_started_at":null}}"#

@Test func readerFollowsPagesAndPreservesQuestionTypes() async throws {
    let reader = WaniKaniReader { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(request.value(forHTTPHeaderField: "Wanikani-Revision") == "20170710")
        let url = request.url!
        switch url.path {
        case "/v2/user": return response(request, user)
        case "/v2/subjects":
            if url.query?.contains("page_after_id") == true {
                return response(request, #"{"pages":{"next_url":null},"data":[{"id":2,"object":"kana_vocabulary","data":{"characters":"はい","meanings":[{"meaning":"Yes","primary":true}],"readings":null,"level":1,"hidden_at":null,"document_url":"https://www.wanikani.com/vocabulary/はい"}}]}"#)
            }
            return response(request, #"{"pages":{"next_url":"https://api.wanikani.com/v2/subjects?page_after_id=1"},"data":[{"id":1,"object":"kanji","data":{"characters":"一","meanings":[{"meaning":"One","primary":true}],"readings":[{"reading":"いち"}],"level":1,"hidden_at":null}}]}"#)
        case "/v2/assignments": return response(request, #"{"pages":{"next_url":null},"data":[{"data":{"subject_id":1,"srs_stage":5,"available_at":"2026-10-17T00:00:00.000000Z"}}]}"#)
        default: return response(request, emptyPage)
        }
    }
    let result = try await reader.fetch(token: "fixture-token")
    #expect(result.subjects.map(\.kind) == [.kanji, .vocabulary])
    #expect(result.subjects.first?.readings == ["いち"])
    #expect(result.assignments.first?.hasAvailableAt == true)
    #expect(result.currentLevel == 12 && !result.onVacation && !result.isSample)
}

@Test func readerRejectsForeignPaginationBeforeSendingToken() async {
    let reader = WaniKaniReader { request in
        #expect(request.url?.host == "api.wanikani.com")
        if request.url?.path == "/v2/user" { return response(request, user) }
        return response(request, #"{"pages":{"next_url":"https://other.invalid/v2/subjects"},"data":[]}"#)
    }
    await #expect(throws: WaniKaniReader.ReaderError.self) { try await reader.fetch(token: "fixture-token") }
}

@Test func readerRejectsPaginationLoop() async {
    let reader = WaniKaniReader { request in
        if request.url?.path == "/v2/user" { return response(request, user) }
        return response(request, #"{"pages":{"next_url":"https://api.wanikani.com/v2/assignments"},"data":[]}"#)
    }
    await #expect(throws: WaniKaniReader.ReaderError.self) { try await reader.fetch(token: "fixture-token") }
}

@Test func failedEndpointDoesNotPublishPartialSnapshot() async {
    let reader = WaniKaniReader { request in
        if request.url?.path == "/v2/user" { return response(request, user) }
        if request.url?.path == "/v2/assignments" { return response(request, "{}", status: 401) }
        return response(request, emptyPage)
    }
    await #expect(throws: WaniKaniReader.ReaderError.self) { try await reader.fetch(token: "fixture-token") }
}
