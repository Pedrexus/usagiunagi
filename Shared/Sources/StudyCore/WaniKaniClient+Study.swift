import Foundation

public struct WaniKaniAccount: Sendable {
  public let id: String
  public let username: String
  public let level: Int
  public let onVacation: Bool
  public let startedAt: Int64?
  public let profile: StudyAccountProfile?
  public init(
    id: String, username: String, level: Int, onVacation: Bool, startedAt: Int64? = nil,
    profile: StudyAccountProfile? = nil
  ) {
    self.id = id
    self.username = username
    self.level = level
    self.onVacation = onVacation
    self.startedAt = startedAt
    self.profile = profile
  }
}

public struct WaniKaniMaterial: Codable, Equatable, Sendable {
  public let id: Int64
  public let value: StudyMaterial
  public init(id: Int64, value: StudyMaterial) {
    self.id = id
    self.value = value
  }
}

extension WaniKaniClient {
  struct AccountData: Decodable, Sendable {
    let id: String
    let username: String
    let level: Int
    let currentVacationStartedAt: String?
    let profileUrl: String?
    let startedAt: String?
    let subscription: Subscription?
    struct Subscription: Decodable, Sendable {
      let active: Bool
      let maxLevelGranted: Int
      let periodEndsAt: String?
    }
  }
  struct AssignmentData: Decodable, Sendable {
    let subjectId: Int64
    let subjectType: String
    let srsStage: Int
    let availableAt: String?
    let startedAt: String?
    let unlockedAt: String?
    let passedAt: String?
    let burnedAt: String?
    let resurrectedAt: String?
    let hidden: Bool?
  }
  struct MaterialData: Codable, Sendable {
    let subjectId: Int64
    let meaningNote: String?
    let readingNote: String?
    let meaningSynonyms: [String]
    var value: StudyMaterial {
      .init(
        subjectID: subjectId, meaningNote: meaningNote ?? "", readingNote: readingNote ?? "",
        meaningSynonyms: meaningSynonyms)
    }
  }
  private struct ReviewResponse: Decodable, Sendable {
    struct Review: Decodable, Sendable {
      let assignmentId: Int64
      let subjectId: Int64
      let incorrectMeaningAnswers: Int
      let incorrectReadingAnswers: Int
      let endingSrsStage: Int
    }
    struct Updates: Decodable, Sendable { let assignment: Resource<AssignmentData> }
    let id: Int64
    let object: String
    let data: Review
    let resourcesUpdated: Updates
  }

  public func account(token: String) async throws -> WaniKaniAccount {
    let user = try await accountData(token: token)
    return .init(
      id: user.id, username: user.username, level: user.level,
      onVacation: user.currentVacationStartedAt != nil,
      startedAt: try user.startedAt.map(timestamp), profile: try accountProfile(user)
    )
  }

  func accountProfile(_ user: AccountData) throws -> StudyAccountProfile? {
    guard let profileURL = user.profileUrl, let startedAt = user.startedAt,
      let subscription = user.subscription
    else { return nil }
    guard (0...60).contains(subscription.maxLevelGranted) else { throw APIError.invalidResponse }
    var profile = StudyAccountProfile(username: user.username)
    profile.level = user.level
    profile.profileURL = profileURL
    profile.startedAt = try timestamp(startedAt)
    profile.subscribed = subscription.active
    profile.maxLevelGranted = subscription.maxLevelGranted
    profile.subscriptionEndsAt = try subscription.periodEndsAt.map(timestamp)
    profile.vacationStartedAt = try user.currentVacationStartedAt.map(timestamp)
    return profile
  }

  func accountData(token: String) async throws -> AccountData {
    let resource: Resource<AccountData> = try await request(endpoint("user"), token: token)
    let user = resource.data
    guard resource.object == "user", !user.id.isEmpty, !user.username.isEmpty,
      (1...60).contains(user.level)
    else { throw APIError.invalidResponse }
    _ = try timestamp(user.currentVacationStartedAt)
    return user
  }

  /// Query by subject because WaniKani can replace assignment IDs. Missing/duplicate records
  /// are not proof that a pending answer succeeded.
  public func assignment(subjectID: Int64, token: String) async throws -> CatalogAssignment? {
    guard subjectID > 0 else { throw APIError.invalidPayload }
    let rows: [Resource<AssignmentData>] = try await pages(
      "assignments?subject_ids=\(subjectID)", token: token)
    guard rows.count <= 1 else { throw APIError.invalidResponse }
    return try rows.first.map { try assignment($0, subjectID: subjectID) }
  }

  public func material(subjectID: Int64, token: String) async throws -> WaniKaniMaterial? {
    guard subjectID > 0 else { throw APIError.invalidPayload }
    let rows: [Resource<MaterialData>] = try await pages(
      "study_materials?subject_ids=\(subjectID)", token: token)
    guard rows.count <= 1 else { throw APIError.invalidResponse }
    return try rows.first.map { try material($0, subjectID: subjectID) }
  }

  /// Caller must durably mark the attempt first. This method makes exactly one write request.
  /// A transport failure, cancellation or malformed success leaves its remote outcome unknown.
  public func submit(_ answer: StudyReviewSubmission, token: String, now: Date = Date())
    async throws -> CatalogAssignment
  {
    guard answer.subjectID > 0, answer.assignmentID > 0, answer.meaningWrongCount >= 0,
      answer.readingWrongCount >= 0
    else { throw APIError.invalidPayload }
    if answer.isLesson {
      struct Body: Encodable {
        struct Assignment: Encodable { let startedAt: String? }
        let assignment: Assignment
      }
      let body = Body(assignment: .init(startedAt: answer.createdAt.map(dateString)))
      let resource: Resource<AssignmentData> = try await request(
        endpoint("assignments/\(answer.assignmentID)/start"),
        token: token, method: .put, body: encode(body))
      let result = try assignment(resource, subjectID: answer.subjectID)
      guard result.id == answer.assignmentID, result.startedAt != nil, result.srsStage > 0 else {
        throw APIError.invalidResponse
      }
      return result
    }
    struct Body: Encodable {
      struct Review: Encodable {
        let assignmentId: Int64
        let incorrectMeaningAnswers: Int
        let incorrectReadingAnswers: Int
        let createdAt: String?
      }
      let review: Review
    }
    // Preserve the existing clock-drift allowance for recent reviews.
    let recordedAt = answer.createdAt.flatMap {
      now.timeIntervalSince1970 - Double($0) > 900 ? dateString($0) : nil
    }
    let body = Body(
      review: .init(
        assignmentId: answer.assignmentID, incorrectMeaningAnswers: answer.meaningWrongCount,
        incorrectReadingAnswers: answer.readingWrongCount, createdAt: recordedAt))
    let response: ReviewResponse = try await request(
      endpoint("reviews"), token: token, method: .post, body: encode(body))
    let result = try assignment(response.resourcesUpdated.assignment, subjectID: answer.subjectID)
    guard response.object == "review", response.id >= 0,
      response.data.subjectId == answer.subjectID,
      response.data.assignmentId == answer.assignmentID, result.id == answer.assignmentID,
      response.data.incorrectMeaningAnswers == answer.meaningWrongCount,
      response.data.incorrectReadingAnswers == answer.readingWrongCount,
      response.data.endingSrsStage == result.srsStage
    else { throw APIError.invalidResponse }
    return result
  }

  /// Always look up the subject before choosing POST/PUT, including after an uncertain create.
  /// The repository must serialize material writes and acknowledge only the sent local revision.
  public func saveMaterial(_ value: StudyMaterial, token: String) async throws -> WaniKaniMaterial {
    guard value.subjectID > 0 else { throw APIError.invalidPayload }
    let existing = try await material(subjectID: value.subjectID, token: token)
    return try await writeMaterial(value, serverID: existing?.id, token: token)
  }

  /// Supply an ID from a fresh subject lookup. A durable caller can record its exact attempt
  /// between that read and this single write, retaining uncertainty across process termination.
  public func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) async throws
    -> WaniKaniMaterial
  {
    guard value.subjectID > 0, serverID == nil || serverID! > 0 else {
      throw APIError.invalidPayload
    }
    struct Body: Encodable {
      struct Material: Encodable {
        let subjectId: Int64?
        let meaningNote: String
        let readingNote: String
        let meaningSynonyms: [String]
      }
      let studyMaterial: Material
    }
    let body = Body(
      studyMaterial: .init(
        subjectId: serverID == nil ? value.subjectID : nil,
        meaningNote: value.meaningNote, readingNote: value.readingNote,
        meaningSynonyms: value.meaningSynonyms))
    let path = serverID.map { "study_materials/\($0)" } ?? "study_materials"
    let response: Resource<MaterialData> = try await request(
      endpoint(path), token: token,
      method: serverID == nil ? .post : .put, body: encode(body))
    let result = try material(response, subjectID: value.subjectID)
    guard result.value == value, serverID == nil || result.id == serverID else {
      throw APIError.invalidResponse
    }
    return result
  }

  func assignment(_ resource: Resource<AssignmentData>, subjectID: Int64) throws
    -> CatalogAssignment
  {
    guard resource.object == "assignment", let id = resource.id, id > 0,
      resource.data.subjectId == subjectID, resource.data.srsStage >= 0
    else { throw APIError.invalidResponse }
    let data = resource.data
    var value = CatalogAssignment(id: id, subjectID: subjectID, kind: try kind(data.subjectType))
    value.srsStage = data.srsStage
    value.hidden = data.hidden
    value.isKanaOnlyVocabulary = data.subjectType == "kana_vocabulary"
    value.availableAt = try data.availableAt.map(timestamp)
    value.startedAt = try data.startedAt.map(timestamp)
    value.unlockedAt = try data.unlockedAt.map(timestamp)
    value.passedAt = try data.passedAt.map(timestamp)
    value.burnedAt = try data.burnedAt.map(timestamp)
    value.resurrectedAt = try data.resurrectedAt.map(timestamp)
    return value
  }
  func material(_ resource: Resource<MaterialData>, subjectID: Int64) throws -> WaniKaniMaterial {
    guard resource.object == "study_material", let id = resource.id, id > 0,
      resource.data.subjectId == subjectID
    else { throw APIError.invalidResponse }
    return .init(id: id, value: resource.data.value)
  }
  func encode(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try encoder.encode(value)
  }
  private func dateString(_ seconds: Int64) -> String {
    ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(seconds)))
  }
}
