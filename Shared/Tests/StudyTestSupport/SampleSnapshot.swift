import Foundation
import StudyCore

extension StudySnapshot {
  /// Synthetic preview data only. Never saved as an authenticated account snapshot.
  public static func sample(now: Date = .now) throws -> StudySnapshot {
    let library = try CurriculumLibrary.bundled()
    let characters = library.entries.filter {
      (1...6).contains($0.value.grade ?? 0) || $0.value.grade == 8
    }
    .sorted { ($0.value.grade ?? 8, $0.key) < ($1.value.grade ?? 8, $1.key) }
    let subjects = characters.enumerated().map { i, entry in
      StudySubject(
        id: Int64(i + 1), characters: entry.key, meaning: "Sample kanji", level: min(60, i / 35 + 1)
      )
    }
    let assignments = subjects.prefix(1100).enumerated().map { i, subject in
      StudyAssignment(
        subjectID: subject.id, srsStageNumber: 1 + (i % 9),
        availableAt: Int64(now.timeIntervalSince1970) + Int64((i % 160) * 3600 - 7200))
    }
    let statistics = assignments.enumerated().map { i, a in
      StudyAnswerStatistics(
        subjectID: a.subjectID, meaningCorrect: 28, meaningIncorrect: i % 5,
        meaningCurrentStreak: i % 9, readingCorrect: 20, readingIncorrect: i % 7,
        readingCurrentStreak: i % 6)
    }
    var start = now.addingTimeInterval(-95 * 86400)
    var levels = [StudyLevel]()
    for (index, days) in [10, 12, 11, 14, 9, 13, 12, 13].enumerated() {
      let end = start.addingTimeInterval(Double(days) * 86400)
      levels.append(
        .init(
          level: Int32(index + 16), unlockedAt: Int64(start.timeIntervalSince1970),
          passedAt: Int64(end.timeIntervalSince1970)))
      start = end
    }
    levels.append(.init(level: 24, unlockedAt: Int64(now.timeIntervalSince1970 - 86400)))
    return StudySnapshot(
      username: "Sample learner", currentLevel: 24, assignments: assignments,
      statistics: statistics, levels: levels, subjects: subjects, savedAt: now, isSample: true)
  }
}
