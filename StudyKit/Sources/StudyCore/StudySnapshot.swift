import Foundation

public enum SubjectKind: String, Codable, Sendable { case radical, kanji, vocabulary }

public struct StudySubject: Codable, Identifiable, Sendable {
    public let id: Int64
    public let characters: String
    public let meaning: String
    public let readings: [String]
    public let kind: SubjectKind
    public let level: Int
    public let documentURL: URL?
    public init(id: Int64, characters: String, meaning: String, readings: [String] = [],
                kind: SubjectKind = .kanji, level: Int = 1, documentURL: URL? = nil) {
        self.id = id; self.characters = characters; self.meaning = meaning
        self.readings = readings; self.kind = kind; self.level = level; self.documentURL = documentURL
    }
}

public struct StudyAssignment: Codable, Sendable {
    public let subjectID: Int64
    public let srsStageNumber: Int
    public let availableAt: Int64
    public var hasAvailableAt: Bool { availableAt > 0 }
    public init(subjectID: Int64, srsStageNumber: Int, availableAt: Int64 = 0) {
        self.subjectID = subjectID; self.srsStageNumber = srsStageNumber; self.availableAt = availableAt
    }
}

public struct StudyAnswerStatistics: Codable, Sendable {
    public let subjectID: Int64
    public let type: SubjectKind
    public let meaningCorrect: Int
    public let meaningIncorrect: Int
    public let meaningCurrentStreak: Int
    public let readingCorrect: Int
    public let readingIncorrect: Int
    public let readingCurrentStreak: Int
    public let hidden: Bool
    public init(subjectID: Int64, type: SubjectKind = .kanji, meaningCorrect: Int = 0,
                meaningIncorrect: Int = 0, meaningCurrentStreak: Int = 0, readingCorrect: Int = 0,
                readingIncorrect: Int = 0, readingCurrentStreak: Int = 0, hidden: Bool = false) {
        self.subjectID = subjectID; self.type = type; self.meaningCorrect = meaningCorrect
        self.meaningIncorrect = meaningIncorrect; self.meaningCurrentStreak = meaningCurrentStreak
        self.readingCorrect = readingCorrect; self.readingIncorrect = readingIncorrect
        self.readingCurrentStreak = readingCurrentStreak; self.hidden = hidden
    }
}

public struct StudyLevel: Codable, Sendable {
    public let level: Int32
    public let unlockedAt: Int64
    public let passedAt: Int64
    public let abandonedAt: Int64
    public var hasUnlockedAt: Bool { unlockedAt > 0 }
    public var hasPassedAt: Bool { passedAt > 0 }
    public var hasAbandonedAt: Bool { abandonedAt > 0 }
    public init(level: Int32, unlockedAt: Int64, passedAt: Int64 = 0, abandonedAt: Int64 = 0) {
        self.level = level; self.unlockedAt = unlockedAt; self.passedAt = passedAt; self.abandonedAt = abandonedAt
    }
}

/// A complete, immutable account snapshot. No credentials or upload queue are stored here.
public struct StudySnapshot: Codable, Sendable {
    /// Stable WaniKani user ID; absent only in older caches and synthetic samples.
    public let accountID: String?
    public let username: String
    public let currentLevel: Int
    public let onVacation: Bool
    public let assignments: [StudyAssignment]
    public let statistics: [StudyAnswerStatistics]
    public let levels: [StudyLevel]
    public let subjects: [StudySubject]
    public let savedAt: Date
    public let pendingReviews: Int
    public let isSample: Bool
    public init(accountID: String? = nil, username: String, currentLevel: Int, onVacation: Bool = false,
                assignments: [StudyAssignment], statistics: [StudyAnswerStatistics], levels: [StudyLevel],
                subjects: [StudySubject], savedAt: Date = .now, pendingReviews: Int = 0, isSample: Bool = false) {
        self.accountID = accountID; self.username = username; self.currentLevel = currentLevel; self.onVacation = onVacation
        self.assignments = assignments; self.statistics = statistics; self.levels = levels
        self.subjects = subjects; self.savedAt = savedAt; self.pendingReviews = pendingReviews; self.isSample = isSample
    }
    public func metrics(now: Date = .now) -> StudyMetrics {
        StudyMetrics(assignments: assignments, statistics: statistics, levels: levels,
                     currentLevel: currentLevel, onVacation: onVacation, now: now)
    }
}
