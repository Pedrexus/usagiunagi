import Foundation

/// Server-owned preferences. Deprecated voice/lesson-order fields are deliberately not controls.
public struct WaniKaniPreferences: Codable, Equatable, Sendable {
  public enum Context: Sendable { case lessons, reviews, extraStudy }
  public enum ReviewOrder: String, Codable, CaseIterable, Sendable {
    case shuffled
    case lowerLevelsFirst = "lower_levels_first"
  }
  public var extraStudyAutoplayAudio: Bool
  public var lessonsAutoplayAudio: Bool
  public var lessonsBatchSize: Int
  public var reviewsAutoplayAudio: Bool
  public var reviewsDisplaySrsIndicator: Bool
  /// Keep unfamiliar server values readable; editing offers only documented options.
  public var reviewsPresentationOrder: String

  public var reviewOrder: StudyReviewOrder? {
    switch ReviewOrder(rawValue: reviewsPresentationOrder) {
    case .shuffled: .random
    case .lowerLevelsFirst: .lowestLevelFirst
    case nil: nil
    }
  }
  public func autoplay(in context: Context) -> Bool {
    switch context {
    case .lessons: lessonsAutoplayAudio
    case .reviews: reviewsAutoplayAudio
    case .extraStudy: extraStudyAutoplayAudio
    }
  }

  public func applying(_ changes: WaniKaniPreferenceChanges) -> Self {
    var value = self
    if let edit = changes.extraStudyAutoplayAudio { value.extraStudyAutoplayAudio = edit }
    if let edit = changes.lessonsAutoplayAudio { value.lessonsAutoplayAudio = edit }
    if let edit = changes.lessonsBatchSize { value.lessonsBatchSize = edit }
    if let edit = changes.reviewsAutoplayAudio { value.reviewsAutoplayAudio = edit }
    if let edit = changes.reviewsDisplaySrsIndicator { value.reviewsDisplaySrsIndicator = edit }
    if let edit = changes.reviewsPresentationOrder {
      value.reviewsPresentationOrder = edit.rawValue
    }
    return value
  }
}

/// Nil fields are absent from the PUT, so one edited option cannot replace unrelated settings.
public struct WaniKaniPreferenceChanges: Codable, Equatable, Sendable {
  public var extraStudyAutoplayAudio: Bool?
  public var lessonsAutoplayAudio: Bool?
  public var lessonsBatchSize: Int?
  public var reviewsAutoplayAudio: Bool?
  public var reviewsDisplaySrsIndicator: Bool?
  public var reviewsPresentationOrder: WaniKaniPreferences.ReviewOrder?
  public init() {}

  public init(from old: WaniKaniPreferences, to new: WaniKaniPreferences) {
    if old.extraStudyAutoplayAudio != new.extraStudyAutoplayAudio {
      extraStudyAutoplayAudio = new.extraStudyAutoplayAudio
    }
    if old.lessonsAutoplayAudio != new.lessonsAutoplayAudio {
      lessonsAutoplayAudio = new.lessonsAutoplayAudio
    }
    if old.lessonsBatchSize != new.lessonsBatchSize { lessonsBatchSize = new.lessonsBatchSize }
    if old.reviewsAutoplayAudio != new.reviewsAutoplayAudio {
      reviewsAutoplayAudio = new.reviewsAutoplayAudio
    }
    if old.reviewsDisplaySrsIndicator != new.reviewsDisplaySrsIndicator {
      reviewsDisplaySrsIndicator = new.reviewsDisplaySrsIndicator
    }
    if old.reviewsPresentationOrder != new.reviewsPresentationOrder {
      reviewsPresentationOrder = .init(rawValue: new.reviewsPresentationOrder)
    }
  }

  public var isEmpty: Bool {
    extraStudyAutoplayAudio == nil && lessonsAutoplayAudio == nil && lessonsBatchSize == nil
      && reviewsAutoplayAudio == nil && reviewsDisplaySrsIndicator == nil
      && reviewsPresentationOrder == nil
  }

  public mutating func merge(_ edits: Self) {
    if let value = edits.extraStudyAutoplayAudio { extraStudyAutoplayAudio = value }
    if let value = edits.lessonsAutoplayAudio { lessonsAutoplayAudio = value }
    if let value = edits.lessonsBatchSize { lessonsBatchSize = value }
    if let value = edits.reviewsAutoplayAudio { reviewsAutoplayAudio = value }
    if let value = edits.reviewsDisplaySrsIndicator { reviewsDisplaySrsIndicator = value }
    if let value = edits.reviewsPresentationOrder { reviewsPresentationOrder = value }
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

  /// Verify identity before one PUT; a read can confirm an earlier uncertain write without replay.
  public func updateUserPreferences(
    _ changes: WaniKaniPreferenceChanges, accountID: String, token: String
  ) async throws -> WaniKaniPreferences {
    guard !changes.isEmpty else { throw WaniKaniPreferenceError.emptyChanges }
    guard changes.lessonsBatchSize.map({ $0 > 0 }) != false else {
      throw WaniKaniPreferenceError.invalidBatchSize
    }
    let current = try await userPreferences(accountID: accountID, token: token)
    if changes.matches(current) { return current }
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
