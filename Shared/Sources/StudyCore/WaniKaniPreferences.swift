import Foundation

/// Server-owned preferences. Deprecated voice/lesson-order fields are deliberately not controls.
public struct WaniKaniPreferences: Codable, Equatable, Sendable {
  public enum ReviewOrder: String, Codable, CaseIterable, Sendable {
    case shuffled
    case lowerLevelsFirst = "lower_levels_first"
  }
  public let extraStudyAutoplayAudio: Bool
  public let lessonsAutoplayAudio: Bool
  public let lessonsBatchSize: Int
  public let reviewsAutoplayAudio: Bool
  public let reviewsDisplaySrsIndicator: Bool
  /// Keep unfamiliar server values readable; editing offers only documented options.
  public let reviewsPresentationOrder: String
}

/// Nil fields are absent from the PUT, so one edited option cannot replace unrelated settings.
public struct WaniKaniPreferenceChanges: Encodable, Sendable {
  public var extraStudyAutoplayAudio: Bool?
  public var lessonsAutoplayAudio: Bool?
  public var lessonsBatchSize: Int?
  public var reviewsAutoplayAudio: Bool?
  public var reviewsDisplaySrsIndicator: Bool?
  public var reviewsPresentationOrder: WaniKaniPreferences.ReviewOrder?
  public init() {}

  var isEmpty: Bool {
    extraStudyAutoplayAudio == nil && lessonsAutoplayAudio == nil && lessonsBatchSize == nil
      && reviewsAutoplayAudio == nil && reviewsDisplaySrsIndicator == nil
      && reviewsPresentationOrder == nil
  }

  func matches(_ value: WaniKaniPreferences) -> Bool {
    let booleans: [(Bool?, Bool)] = [
      (extraStudyAutoplayAudio, value.extraStudyAutoplayAudio),
      (lessonsAutoplayAudio, value.lessonsAutoplayAudio),
      (reviewsAutoplayAudio, value.reviewsAutoplayAudio),
      (reviewsDisplaySrsIndicator, value.reviewsDisplaySrsIndicator),
    ]
    return booleans.allSatisfy { $0.0 == nil || $0.0 == $0.1 }
      && (lessonsBatchSize == nil || lessonsBatchSize == value.lessonsBatchSize)
      && (reviewsPresentationOrder == nil
        || reviewsPresentationOrder?.rawValue == value.reviewsPresentationOrder)
  }
}

public enum WaniKaniPreferenceError: Error, LocalizedError, Equatable, Sendable {
  case unsupported, permissionDenied, emptyChanges, invalidBatchSize
  public var errorDescription: String? {
    switch self {
    case .unsupported: "This connection does not support WaniKani settings."
    case .permissionDenied:
      "This token cannot change WaniKani settings. Enable user:update permission or change these settings on WaniKani."
    case .emptyChanges: "No WaniKani settings were changed."
    case .invalidBatchSize: "The lesson batch size must be a positive number."
    }
  }
}

extension WaniKaniService {
  /// Injected services do not silently acquire the production transport.
  public func userPreferences(accountID: String, token: String) async throws -> WaniKaniPreferences
  {
    throw WaniKaniPreferenceError.unsupported
  }
  public func updateUserPreferences(
    _ changes: WaniKaniPreferenceChanges, accountID: String, token: String
  ) async throws -> WaniKaniPreferences {
    throw WaniKaniPreferenceError.unsupported
  }
}

extension WaniKaniClient {
  private struct PreferenceUser: Decodable, Sendable {
    let id: String
    let preferences: WaniKaniPreferences
  }

  public func userPreferences(accountID: String, token: String) async throws -> WaniKaniPreferences
  {
    let response: Resource<PreferenceUser> = try await request(endpoint("user"), token: token)
    return try preferences(response, accountID: accountID)
  }

  /// Verify identity before one explicit PUT; ambiguous writes are never automatically replayed.
  public func updateUserPreferences(
    _ changes: WaniKaniPreferenceChanges, accountID: String, token: String
  ) async throws -> WaniKaniPreferences {
    guard !changes.isEmpty else { throw WaniKaniPreferenceError.emptyChanges }
    guard changes.lessonsBatchSize.map({ $0 > 0 }) != false else {
      throw WaniKaniPreferenceError.invalidBatchSize
    }
    _ = try await userPreferences(accountID: accountID, token: token)
    try Task.checkCancellation()
    let response: Resource<PreferenceUser> = try await request(
      endpoint("user"), token: token, method: .put,
      body: encode(["user": ["preferences": changes]]))
    let value = try preferences(response, accountID: accountID)
    guard changes.matches(value) else { throw APIError.invalidResponse }
    return value
  }

  private func preferences(_ response: Resource<PreferenceUser>, accountID: String) throws
    -> WaniKaniPreferences
  {
    guard response.object == "user", !accountID.isEmpty, !response.data.id.isEmpty,
      response.data.preferences.lessonsBatchSize > 0
    else { throw APIError.invalidResponse }
    guard response.data.id == accountID else { throw StudySignInError.accountMismatch }
    return response.data.preferences
  }
}
