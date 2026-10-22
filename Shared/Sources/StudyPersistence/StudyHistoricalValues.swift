import Foundation
import StudyCore

/// Historical V1 payload identities. These values only decode receipts already in SwiftData.
/// Keep the stored fields unchanged until a versioned schema preserves independent V1 decoders.
public struct StudyLegacyHandoff: Codable, Equatable, Sendable {
  public let sourceID: String
  public let accountID: String
  public let credentialID: String
  public let preferences: LegacyStudyPreferences?
  public fileprivate(set) var activated = false
  public fileprivate(set) var mistakeAccess: StudyLegacyMistakeAccess? = nil
  var receiptID: String { "ios:" + accountID + ":" + sourceID }
}

public struct StudyLegacyMistakeBinding: Codable, Equatable, Sendable {
  public let accountID: String
  public let sourceID: String
  public let sourceDigest: String
  public let username: String
  public let context: StudyLegacyMistakeContext
}

public enum StudyLegacyMistakeAccess: Codable, Equatable, Sendable {
  case active(StudyLegacyMistakeBinding)
  case revoked(StudyLegacyMistakeBinding)
}
