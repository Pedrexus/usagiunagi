import Foundation

public enum StudyPracticeScope: String, Codable, CaseIterable, Identifiable, Sendable {
  case apprentice, recentLessons, recentMistakes, leeches, burned
  public var id: Self { self }
  public var title: String {
    switch self {
    case .apprentice: "Extra practice"
    case .recentLessons: "Recent lessons"
    case .recentMistakes: "Recent mistakes"
    case .leeches: "Leech training"
    case .burned: "Burned items"
    }
  }
}

public enum StudySRSCategory: Int, CaseIterable, Sendable {
  case apprentice, guru, master, enlightened, burned
  public var name: String {
    switch self {
    case .apprentice: "Apprentice"
    case .guru: "Guru"
    case .master: "Master"
    case .enlightened: "Enlightened"
    case .burned: "Burned"
    }
  }
  public var catalogScope: SubjectCatalogScope {
    switch self {
    case .apprentice: .apprentice
    case .guru: .guru
    case .master: .master
    case .enlightened: .enlightened
    case .burned: .burned
    }
  }
}

extension StudySRSStage {
  public var category: StudySRSCategory {
    switch self {
    case .apprentice1, .apprentice2, .apprentice3, .apprentice4: .apprentice
    case .guru1, .guru2: .guru
    case .master: .master
    case .enlightened: .enlightened
    case .burned: .burned
    }
  }
}

/// Shared selection rules for Home counts and the sessions those buttons actually open.
public struct StudyAvailability: Sendable {
  public let account: StudyAccountState
  public let subjects: [CatalogSubject]
  public let assignments: [CatalogAssignment]
  public let pending: Set<Int64>
  public let excluded: Set<Int64>
  public let lessonPreferences: StudyLessonPreferences
  public let now: Date
  private let byID: [Int64: CatalogSubject]
  private let calendar: Calendar
  private let leechThreshold: Double

  public init(
    account: StudyAccountState, subjects: [CatalogSubject], assignments: [CatalogAssignment],
    pending: Set<Int64> = [], excluded: Set<Int64> = [], now: Date = .now,
    calendar: Calendar = .current, leechThreshold: Double = 1,
    lessonPreferences: StudyLessonPreferences = .init()
  ) {
    self.lessonPreferences = lessonPreferences.normalized
    self.account = account
    self.subjects = subjects
    self.assignments = assignments
    self.pending = pending
    self.excluded = excluded
    self.now = now
    self.calendar = calendar
    self.leechThreshold = leechThreshold.isFinite && leechThreshold > 0 ? leechThreshold : 1
    byID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }
  private var accessible: [CatalogAssignment] {
    assignments.filter { item in
      guard item.hidden != true, !pending.contains(item.subjectID) else { return false }
      // Session opening must report missing content instead of silently omitting the item.
      guard let subject = byID[item.subjectID] else { return true }
      return subject.hiddenAt == nil && subject.level <= account.profile.maxLevelGranted
    }
  }
  private func includes(_ item: CatalogAssignment) -> Bool {
    lessonPreferences.includeKanaVocabulary
      || !(item.isKanaOnlyVocabulary || byID[item.subjectID]?.isKanaOnlyVocabulary == true)
  }
  public var apprenticeCount: Int {
    assignments.filter { item in
      (1...4).contains(item.srsStage) && item.hidden != true
        && byID[item.subjectID]?.hiddenAt == nil
    }.count
  }
  public var apprenticeLimitReached: Bool { apprenticeCount >= lessonPreferences.apprenticeLimit }
  public var scheduled: [CatalogAssignment] {
    scheduledFuture.filter {
      $0.availableAt.map { Double($0) <= now.timeIntervalSince1970 } == true
    }
    .sorted { ($0.availableAt ?? 0, $0.subjectID) < ($1.availableAt ?? 0, $1.subjectID) }
  }
  public var scheduledFuture: [CatalogAssignment] {
    accessible.filter {
      includes($0) && $0.startedAt != nil && (1...8).contains($0.srsStage) && $0.availableAt != nil
        && ($0.kind != .vocabulary || !excluded.contains($0.subjectID))
    }
  }
  public var lessons: [CatalogAssignment] {
    accessible.filter {
      includes($0) && $0.unlockedAt != nil && $0.startedAt == nil && $0.srsStage == 0
        && ($0.kind != .vocabulary || !excluded.contains($0.subjectID))
    }
    .sorted {
      lessonPreferences.precedes(
        (level: $0.level, kind: $0.kind, subjectID: $0.subjectID),
        (level: $1.level, kind: $1.kind, subjectID: $1.subjectID))
    }
  }
  public func practice(_ scope: StudyPracticeScope) -> [CatalogAssignment] {
    let mistakes = Set(account.progress.filter { recentMistake($0) }.map(\.subjectID))
    let statistics = Dictionary(
      account.statistics.map { ($0.answers.subjectID, $0.answers) },
      uniquingKeysWith: { first, _ in first })
    return accessible.filter { item in
      guard includes(item), item.startedAt != nil, (1...9).contains(item.srsStage) else {
        return false
      }
      switch scope {
      case .apprentice: return item.srsStage <= 4 && item.passedAt != nil
      case .recentLessons:
        return item.srsStage <= 4 && item.passedAt == nil && item.availableAt != nil
      case .recentMistakes:
        return item.srsStage <= 8 && item.availableAt != nil && mistakes.contains(item.subjectID)
      case .burned: return item.srsStage == 9
      case .leeches:
        guard item.passedAt != nil, item.burnedAt == nil, item.srsStage <= 8,
          let stats = statistics[item.subjectID], !stats.hidden
        else { return false }
        var policy = StudyReviewPolicy()
        policy.leechThreshold = leechThreshold
        return policy.isLeech(
          stats,
          hasReading: item.kind != .radical && !item.isKanaOnlyVocabulary
            && byID[item.subjectID]?.isKanaOnlyVocabulary != true)
      }
    }.sorted { $0.subjectID < $1.subjectID }
  }
  private func recentMistake(_ progress: SubjectProgress) -> Bool {
    let date: Date?
    if let epoch = progress.lastMistakeAt {
      date = Date(timeIntervalSince1970: Double(epoch))
    } else if let text = progress.lastMistakeLocalTime {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      formatter.isLenient = false
      date = formatter.date(from: text)
    } else {
      date = nil
    }
    guard let date else { return false }
    return date <= now && date >= now.addingTimeInterval(-86400)
  }
  public var hourlyReviews: [Int] {
    var counts = Array(repeating: 0, count: 25)
    for assignment in scheduledFuture {
      guard let date = assignment.availableAt else { continue }
      let hours = ceil(max(0, Double(date) - now.timeIntervalSince1970) / 3600)
      if hours <= 24 { counts[Int(hours)] += 1 }
    }
    return counts
  }
  public var stageCounts: [Int] {
    StudySRSCategory.allCases.map { category in
      accessible.filter {
        StudySRSStage(rawValue: $0.srsStage)?.category == category
      }.count
    }
  }
  public func progress(level: Int) -> [StudyLevelProgress] {
    let bySubject = Dictionary(
      assignments.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
    return [SubjectKind.radical, .kanji, .vocabulary].map { kind in
      StudyLevelProgress(
        kind: kind,
        stages: subjects.filter {
          $0.level == level && $0.hiddenAt == nil && $0.level <= account.profile.maxLevelGranted
            && $0.kind == kind
            && !pending.contains($0.id)
        }.map { subject in
          guard let assignment = bySubject[subject.id], assignment.hidden != true else {
            return (nil, false)
          }
          return (
            (0...9).contains(assignment.srsStage) ? assignment.srsStage : nil,
            assignment.startedAt != nil
          )
        })
    }
  }
}
