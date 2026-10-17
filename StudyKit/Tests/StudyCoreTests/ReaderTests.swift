import Foundation
import Testing
@testable import StudyCore

private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, HTTPURLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
private let emptyPage = #"{"pages":{"next_url":null},"data":[]}"#
private let user = #"{"object":"user","data":{"id":"fixture-user-id","username":"test","level":12,"current_vacation_started_at":null}}"#

@Test func readerFollowsPagesAndPreservesQuestionTypes() async throws {
    let reader = WaniKaniClient { request in
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
    #expect(result.accountID == "fixture-user-id")
    #expect(result.currentLevel == 12 && !result.onVacation && !result.isSample)
}

@Test func readerRejectsForeignPaginationBeforeSendingToken() async {
    let reader = WaniKaniClient { request in
        #expect(request.url?.host == "api.wanikani.com")
        if request.url?.path == "/v2/user" { return response(request, user) }
        return response(request, #"{"pages":{"next_url":"https://other.invalid/v2/subjects"},"data":[]}"#)
    }
    await #expect(throws: WaniKaniClient.APIError.self) { try await reader.fetch(token: "fixture-token") }
}

@Test func readerRejectsPaginationLoop() async {
    let reader = WaniKaniClient { request in
        if request.url?.path == "/v2/user" { return response(request, user) }
        return response(request, #"{"pages":{"next_url":"https://api.wanikani.com/v2/assignments"},"data":[]}"#)
    }
    await #expect(throws: WaniKaniClient.APIError.self) { try await reader.fetch(token: "fixture-token") }
}

@Test func failedEndpointDoesNotPublishPartialSnapshot() async {
    let reader = WaniKaniClient { request in
        if request.url?.path == "/v2/user" { return response(request, user) }
        if request.url?.path == "/v2/assignments" { return response(request, "{}", status: 401) }
        return response(request, emptyPage)
    }
    await #expect(throws: WaniKaniClient.APIError.self) { try await reader.fetch(token: "fixture-token") }
}

@Test func readerPreservesVacationAndRejectsMissingAccountIdentity() async throws {
    for validIdentity in [true, false] {
        let reader = WaniKaniClient { request in
            if request.url?.path == "/v2/user" {
                let body = validIdentity
                    ? #"{"object":"user","data":{"id":"account-id","username":"test","level":12,"current_vacation_started_at":"2026-10-17T00:00:00Z"}}"#
                    : #"{"object":"user","data":{"username":"test","level":12,"current_vacation_started_at":null}}"#
                return response(request, body)
            }
            return response(request, emptyPage)
        }
        if validIdentity {
            let snapshot = try await reader.fetch(token: "fixture-token")
            #expect(snapshot.onVacation && snapshot.accountID == "account-id")
        } else {
            await #expect(throws: (any Error).self) { try await reader.fetch(token: "fixture-token") }
        }
    }
}
