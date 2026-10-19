import Foundation

private struct LevelReference: Decodable {
  let level: Int
  let kind: SubjectKind
  let characters: String
  let displayReading: String
  let displayMeaning: String
}

extension StudySnapshot {
  /// Display-only catalog with local negative IDs; it cannot supply real review grading or uploads.
  public static func freeLevelsPreview(now: Date = .now) throws -> StudySnapshot {
    let references: [LevelReference] = try StudyResources.decode("free-levels-preview")
    let subjects = references.enumerated().map { index, reference in
      StudySubject(
        id: -Int64(index + 1), characters: reference.characters, meaning: reference.displayMeaning,
        readings: reference.displayReading.isEmpty ? [] : [reference.displayReading],
        kind: reference.kind, level: reference.level)
    }
    return StudySnapshot(
      username: "Levels 1–3 preview", currentLevel: 3, assignments: [], statistics: [], levels: [],
      subjects: subjects, savedAt: now, isSample: true)
  }
}
