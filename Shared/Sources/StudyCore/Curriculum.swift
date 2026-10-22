import Foundation

public enum CurriculumSystem: String, CaseIterable, Identifiable, Sendable {
  case jlpt = "JLPT"
  case school = "School grades"
  case kanken = "Kanji Kentei"
  case joyo = "Jōyō & Kyōiku"
  public var id: String { rawValue }
  public var explanation: String {
    switch self {
    case .jlpt:
      "Estimated kanji lists, including easier levels. This measures kanji coverage, not grammar, listening, vocabulary or exam readiness."
    case .school:
      "Cumulative Japanese school-grade kanji. Grade 6 includes all 1,026 elementary kanji."
    case .kanken:
      "Cumulative official kanji scopes for levels 10–2, including pre-2. Handwriting, readings and other exam skills are not assessed."
    case .joyo:
      "Elementary-school and everyday-use character sets. These describe kanji scope, not test scores."
    }
  }
}

public enum KankenLevel: String, CaseIterable, Codable, Sendable {
  case ten = "10"
  case nine = "9"
  case eight = "8"
  case seven = "7"
  case six = "6"
  case five = "5"
  case four = "4"
  case three = "3"
  case preTwo = "pre2"
  case two = "2"
  public var title: String { self == .preTwo ? "Pre-2" : "Level \(rawValue)" }
}

public struct Curriculum: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let characters: Set<String>
}

public struct CurriculumLibrary: Decodable, Sendable {
  public struct Entry: Decodable, Sendable {
    public let grade: Int?
    public let jlpt: Int?
    public let kanken: KankenLevel?
  }
  public let version: Int
  public let kanjidicDate: String
  public let jlptRevision: String
  public let kankenDocumentSHA256: String
  public let entries: [String: Entry]
  public static func bundled() throws -> Self {
    try StudyResources.decode("curricula")
  }
  public func curricula(for system: CurriculumSystem) -> [Curriculum] {
    func make(_ id: String, _ title: String, _ includes: (Entry) -> Bool) -> Curriculum {
      Curriculum(id: id, title: title, characters: Set(entries.filter { includes($0.value) }.keys))
    }
    switch system {
    case .jlpt:
      return (1...5).reversed().map { n in make("N\(n)", "N\(n)") { ($0.jlpt ?? 0) >= n } }
    case .school:
      return (1...6).map { g in make("grade\(g)", "Grade \(g)") { (1...g).contains($0.grade ?? 0) }
      }
    case .kanken:
      var included = Set<String>()
      return KankenLevel.allCases.map { level in
        included.formUnion(entries.filter { $0.value.kanken == level }.keys)
        return Curriculum(id: "kanken\(level.rawValue)", title: level.title, characters: included)
      }
    case .joyo:
      return [
        make("joyo", "Jōyō") { (1...6).contains($0.grade ?? 0) || $0.grade == 8 },
        make("kyōiku", "Kyōiku") { (1...6).contains($0.grade ?? 0) },
      ]
    }
  }
}

public struct CurriculumCoverage: Identifiable, Sendable {
  public let curriculum: Curriculum
  public let reached: Int
  public let learning: Int
  public let notStarted: Int
  public let awaitingSync: Int
  public let outsideCatalog: Int
  public let remaining: [String]
  public var id: String { curriculum.id }
  public var total: Int { curriculum.characters.count }
  public var fraction: Double { total > 0 ? Double(reached) / Double(total) : 0 }

  public init(
    curriculum: Curriculum, subjects: [StudySubject], assignments: [StudyAssignment],
    threshold: Int = 5, pendingSubjectIDs: Set<Int64> = []
  ) {
    self.curriculum = curriculum
    let threshold = min(
      max(threshold, StudySRSStage.apprentice1.rawValue), StudySRSStage.burned.rawValue)
    let stages = Dictionary(
      assignments.compactMap { assignment -> (Int64, Int)? in
        guard StudySRSStage(rawValue: assignment.srsStageNumber) != nil else { return nil }
        return (assignment.subjectID, assignment.srsStageNumber)
      }, uniquingKeysWith: max)
    let pendingCharacters = Set(
      subjects.filter {
        $0.kind == .kanji && pendingSubjectIDs.contains($0.id)
      }.map(\.characters))
    var byCharacter = [String: Int]()
    for subject in subjects where subject.kind == .kanji {
      byCharacter[subject.characters] = max(
        byCharacter[subject.characters] ?? 0, stages[subject.id] ?? 0)
    }
    var reached = 0
    var learning = 0
    var notStarted = 0
    var awaitingSync = 0
    var outside = 0
    var remaining = [String]()
    for character in curriculum.characters {
      guard let stage = byCharacter[character] else {
        outside += 1
        remaining.append(character)
        continue
      }
      if pendingCharacters.contains(character) {
        awaitingSync += 1
        remaining.append(character)
      } else if stage >= threshold {
        reached += 1
      } else {
        remaining.append(character)
        if stage > 0 { learning += 1 } else { notStarted += 1 }
      }
    }
    self.reached = reached
    self.learning = learning
    self.notStarted = notStarted
    self.awaitingSync = awaitingSync
    outsideCatalog = outside
    self.remaining = remaining.sorted()
  }
}
