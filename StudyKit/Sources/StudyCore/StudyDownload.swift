import Foundation

/// All resources required for offline study, published only after every page succeeds.
/// Local sessions, mistakes and pending writes belong to the repository, not this server value.
public struct StudyDownload: Sendable {
    public let accountID: String
    public var profile: StudyAccountProfile
    public var subjects: [CatalogSubject]
    public var assignments: [CatalogAssignment]
    public var materials: [WaniKaniMaterial]
    public var levels: [CatalogLevelProgression]
    public var statistics: [CatalogReviewStatistic]
    public var voices: [StudyVoiceActor]
    public let fetchedAt: Date

    public init(accountID: String, profile: StudyAccountProfile, subjects: [CatalogSubject] = [],
                assignments: [CatalogAssignment] = [], materials: [WaniKaniMaterial] = [],
                levels: [CatalogLevelProgression] = [], statistics: [CatalogReviewStatistic] = [],
                voices: [StudyVoiceActor] = [], fetchedAt: Date = .now) {
        self.accountID = accountID; self.profile = profile; self.subjects = subjects
        self.assignments = assignments; self.materials = materials; self.levels = levels
        self.statistics = statistics; self.voices = voices; self.fetchedAt = fetchedAt
    }

    public var snapshot: StudySnapshot {
        StudySnapshot(accountID: accountID, username: profile.username, currentLevel: profile.level,
            onVacation: profile.vacationStartedAt != nil, assignments: assignments.filter { $0.hidden != true }.map(\.summary),
            statistics: statistics.map(\.answers), levels: levels.map(\.summary),
            subjects: subjects.filter { $0.hiddenAt == nil }.map(\.summary), savedAt: fetchedAt)
    }
}
