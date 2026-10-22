import Foundation

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
    cursors = download.cursors
    supersededAssignments = []
  }
}
