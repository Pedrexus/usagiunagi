import Foundation

/// A complete, immutable read transaction from the old iOS database. No credentials are included.
/// The original database remains the rollback source, including its diagnostic error log.
public struct LegacyStudyExport: Codable, Sendable {
  public struct Material: Codable, Sendable {
    public let serverID: Int64
    public let value: StudyMaterial
    public let pending: Bool
    public let legacyRevision: Int64
    public init(serverID: Int64, value: StudyMaterial, pending: Bool, legacyRevision: Int64) {
      self.serverID = serverID
      self.value = value
      self.pending = pending
      self.legacyRevision = legacyRevision
    }
  }
  public struct Review: Codable, Sendable {
    public let assignment: CatalogAssignment
    public let submission: StudyReviewSubmission
    public init(assignment: CatalogAssignment, submission: StudyReviewSubmission) {
      self.assignment = assignment
      self.submission = submission
    }
  }
  public var schemaVersion: Int
  public var profile: StudyAccountProfile
  public var subjects: [CatalogSubject] = []
  public var assignments: [CatalogAssignment] = []
  public var supersededAssignments: [CatalogAssignment] = []
  public var pendingReviews: [Review] = []
  public var materials: [Material] = []
  public var progress: [SubjectProgress] = []
  public var levels: [CatalogLevelProgression] = []
  public var statistics: [CatalogReviewStatistic] = []
  public var voices: [StudyVoiceActor] = []
  public var audio: [StudyAudioReference] = []
  public var cursors: [String: String] = [:]
  public init(schemaVersion: Int, profile: StudyAccountProfile) {
    self.schemaVersion = schemaVersion
    self.profile = profile
  }
}

public struct StudyAccountState: Codable, Sendable {
  /// A local study attempt or acknowledgement requires a later complete catalog read.
  public var catalogRefreshID: UUID?
  public var systems: [StudySRSSystem]?
  public var profile: StudyAccountProfile
  public var progress: [SubjectProgress]
  public var levels: [CatalogLevelProgression]
  public var statistics: [CatalogReviewStatistic]
  public var voices: [StudyVoiceActor]
  public var audio: [StudyAudioReference]
  public var cursors: [String: String]
  public var supersededAssignments: [CatalogAssignment]
  public init(download: StudyDownload, progress: [SubjectProgress] = []) {
    systems = download.systems
    profile = download.profile
    self.progress = progress
    levels = download.levels
    statistics = download.statistics
    voices = download.voices
    audio = download.subjects.flatMap { subject in
      subject.audio.map {
        StudyAudioReference(
          subjectID: subject.id, voiceActorID: $0.voiceActorID, level: subject.level, url: $0.url)
      }
    }
    // Full reads do not establish an incremental API watermark.
    cursors = [:]
    supersededAssignments = []
  }
  public init(legacy: LegacyStudyExport) {
    systems = nil
    profile = legacy.profile
    progress = legacy.progress
    levels = legacy.levels
    statistics = legacy.statistics
    voices = legacy.voices
    audio = legacy.audio
    cursors = legacy.cursors
    supersededAssignments = legacy.supersededAssignments
  }
}
