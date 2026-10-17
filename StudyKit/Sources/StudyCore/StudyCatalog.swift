import Foundation

/// Full study content, independent of the legacy protobuf and network representations.
public struct CatalogSubject: Codable, Sendable, Identifiable {
    public struct Meaning: Codable, Sendable {
        public enum Role: Int, Codable, Sendable { case unknown, primary, secondary, auxiliaryWhitelist, blacklist }
        public var text: String
        public var role: Role
        public init(_ text: String, role: Role) { self.text = text; self.role = role }
    }
    public struct Reading: Codable, Sendable {
        public enum Kind: Int, Codable, Sendable { case unknown, onyomi, kunyomi, nanori }
        public var text: String
        public var isPrimary: Bool
        public var kind: Kind
        public init(_ text: String, isPrimary: Bool, kind: Kind) { self.text = text; self.isPrimary = isPrimary; self.kind = kind }
    }
    public struct Sentence: Codable, Sendable {
        public var japanese: String
        public var english: String
        public init(japanese: String, english: String) { self.japanese = japanese; self.english = english }
    }
    public struct Audio: Codable, Sendable {
        public var url: String
        public var voiceActorID: Int64
        public init(url: String, voiceActorID: Int64) { self.url = url; self.voiceActorID = voiceActorID }
    }
    public let id: Int64
    public var kind: SubjectKind
    public var level = 0
    public var slug = ""
    public var documentURL = ""
    public var japanese = ""
    public var readings: [Reading] = []
    public var meanings: [Meaning] = []
    public var componentSubjectIDs: [Int64] = []
    public var amalgamationSubjectIDs: [Int64] = []
    public var meaningMnemonic = ""
    public var meaningHint = ""
    public var readingMnemonic = ""
    public var readingHint = ""
    public var deprecatedMnemonic = ""
    public var characterImageURL = ""
    public var hasCharacterImageFile = false
    public var visuallySimilarKanji = ""
    public var visuallySimilarKanjiIDs: [Int64] = []
    public var sentences: [Sentence] = []
    /// Raw documented legacy values are retained, including unknown future parts of speech.
    public var partsOfSpeech: [Int] = []
    public var audio: [Audio] = []
    public init(id: Int64, kind: SubjectKind) { self.id = id; self.kind = kind }
    public var summary: StudySubject {
        StudySubject(id: id, characters: japanese,
            meaning: meanings.first(where: { $0.role == .primary })?.text ?? "",
            readings: readings.map(\.text), kind: kind, level: level, documentURL: URL(string: documentURL))
    }
    public var gradingSubject: GradingSubject {
        GradingSubject(japanese: japanese, kind: kind,
            meanings: meanings.filter { $0.role != .blacklist }.map(\.text),
            blacklistedMeanings: meanings.filter { $0.role == .blacklist }.map(\.text),
            primaryReadings: readings.filter(\.isPrimary).map(\.text),
            alternateReadings: readings.filter { !$0.isPrimary }.map(\.text), componentSubjectIds: componentSubjectIDs)
    }
}

public struct CatalogAssignment: Codable, Sendable, Identifiable {
    public let id: Int64
    public let subjectID: Int64
    public var kind: SubjectKind
    public var level = 0
    public var srsStage = 0
    public var availableAt: Int64?
    public var startedAt: Int64?
    public var passedAt: Int64?
    public var burnedAt: Int64?
    public var unlockedAt: Int64?
    public var resurrectedAt: Int64?
    public var hidden: Bool?
    public var isKanaOnlyVocabulary = false
    public init(id: Int64, subjectID: Int64, kind: SubjectKind) { self.id = id; self.subjectID = subjectID; self.kind = kind }
    public var summary: StudyAssignment {
        StudyAssignment(subjectID: subjectID, srsStageNumber: srsStage, availableAt: availableAt ?? 0)
    }
    public func sessionItem(id: Int, isLesson: Bool) -> StudySessionItem {
        StudySessionItem(id: id, subjectID: subjectID, assignmentID: self.id, srsStage: srsStage,
            availableAt: availableAt ?? 0, isLesson: isLesson, isKanji: kind == .kanji,
            hasMeaning: true, hasReading: kind != .radical && !isKanaOnlyVocabulary)
    }
}

public struct StudyAccountProfile: Codable, Sendable {
    public var username: String
    public var level = 0
    public var maxLevelGranted = 0
    public var profileURL = ""
    public var startedAt: Int64?
    public var subscribed = false
    public var subscriptionEndsAt: Int64?
    public var vacationStartedAt: Int64?
    public init(username: String) { self.username = username }
}

public struct CatalogLevelProgression: Codable, Sendable {
    public let id: Int64
    public var level = 0
    public var abandonedAt: Int64?
    public var completedAt: Int64?
    public var createdAt: Int64?
    public var passedAt: Int64?
    public var startedAt: Int64?
    public var unlockedAt: Int64?
    public init(id: Int64) { self.id = id }
    public var summary: StudyLevel {
        StudyLevel(level: Int32(clamping: level), unlockedAt: unlockedAt ?? 0, passedAt: passedAt ?? 0, abandonedAt: abandonedAt ?? 0)
    }
}

public struct CatalogReviewStatistic: Codable, Sendable {
    public let id: Int64
    public var answers: StudyAnswerStatistics
    public var createdAt: Int64?
    public var meaningMaxStreak = 0
    public var readingMaxStreak = 0
    public var percentageCorrect = 0
    public init(id: Int64, answers: StudyAnswerStatistics) { self.id = id; self.answers = answers }
}

public struct StudyVoiceActor: Codable, Sendable {
    public let id: Int64
    public var name = ""
    public var description = ""
    public var gender = 0
    public init(id: Int64) { self.id = id }
}

public struct SubjectProgress: Codable, Sendable {
    public let subjectID: Int64
    public var level: Int
    public var srsStage: Int
    public var kind: SubjectKind
    /// Preserve the legacy local-time text; never reinterpret it silently as UTC.
    public var lastMistakeLocalTime: String?
    public var legacyRevision: Int64
    public init(subjectID: Int64, level: Int, srsStage: Int, kind: SubjectKind,
                lastMistakeLocalTime: String?, legacyRevision: Int64) {
        self.subjectID = subjectID; self.level = level; self.srsStage = srsStage; self.kind = kind
        self.lastMistakeLocalTime = lastMistakeLocalTime; self.legacyRevision = legacyRevision
    }
}

public struct StudyAudioReference: Codable, Sendable {
    public let subjectID: Int64
    public let voiceActorID: Int64
    public let level: Int
    public let url: String
    public init(subjectID: Int64, voiceActorID: Int64, level: Int, url: String) {
        self.subjectID = subjectID; self.voiceActorID = voiceActorID; self.level = level; self.url = url
    }
}
