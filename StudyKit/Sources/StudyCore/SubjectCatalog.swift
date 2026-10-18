import Foundation

public enum StudySRSStage: Int, CaseIterable, Sendable {
  case apprentice1 = 1
  case apprentice2, apprentice3, apprentice4, guru1, guru2, master, enlightened, burned
  public var name: String {
    switch self {
    case .apprentice1: "Apprentice I"
    case .apprentice2: "Apprentice II"
    case .apprentice3: "Apprentice III"
    case .apprentice4: "Apprentice IV"
    case .guru1: "Guru I"
    case .guru2: "Guru II"
    case .master: "Master"
    case .enlightened: "Enlightened"
    case .burned: "Burned"
    }
  }
}

/// A read-only presentation projection; each platform retains its account-bound storage owner.
public struct SubjectCatalogItem: Identifiable, Sendable {
  public enum Status: Sendable {
    case unassigned, locked, lesson, pending
    case studying(StudySRSStage, reviewAt: Date?, guruAt: Date?)
    public var stage: StudySRSStage? {
      if case .studying(let stage, _, _) = self { stage } else { nil }
    }
    public var name: String {
      switch self {
      case .unassigned: ""
      case .locked: "Locked"
      case .lesson: "Lesson"
      case .pending: "Upload pending"
      case .studying(let stage, _, _): stage.name
      }
    }
  }
  public let subject: CatalogSubject
  public let status: Status
  public let isExcluded: Bool
  public var id: Int64 { subject.id }
  public init(subject: CatalogSubject, status: Status = .unassigned, isExcluded: Bool = false) {
    self.subject = subject
    self.status = status
    self.isExcluded = isExcluded
  }
}

public struct SubjectCatalogCollection: Identifiable, Sendable {
  public let id = UUID()
  public let items: [SubjectCatalogItem]
  public let pendingCount: Int
  public let requiresAssignmentRefresh: Bool
  public init(
    items: [SubjectCatalogItem], pendingCount: Int = 0, requiresAssignmentRefresh: Bool = false
  ) {
    self.items = items
    self.pendingCount = pendingCount
    self.requiresAssignmentRefresh = requiresAssignmentRefresh
  }
}

public enum SubjectCatalogScope: String, CaseIterable, Identifiable, Sendable {
  case all = "All progress"
  case locked = "Locked"
  case lessons = "Lessons"
  case apprentice = "Apprentice"
  case guru = "Guru"
  case master = "Master"
  case enlightened = "Enlightened"
  case burned = "Burned"
  case excluded = "Excluded"
  public var id: Self { self }
  public func contains(_ item: SubjectCatalogItem) -> Bool {
    switch self {
    case .all: true
    case .locked: if case .locked = item.status { true } else { false }
    case .lessons: if case .lesson = item.status { true } else { false }
    case .excluded: item.isExcluded
    case .apprentice: (1...4).contains(item.status.stage?.rawValue ?? 0)
    case .guru: (5...6).contains(item.status.stage?.rawValue ?? 0)
    case .master: item.status.stage == .master
    case .enlightened: item.status.stage == .enlightened
    case .burned: item.status.stage == .burned
    }
  }
}

public struct SubjectCatalogQuery: Hashable, Sendable {
  public var text = ""
  public var level = 0
  public var kind: SubjectKind?
  public var scope = SubjectCatalogScope.all
  public init() {}

  /// Exact matches precede prefixes and substring matches before any result limit is applied.
  @concurrent public func results(in items: [SubjectCatalogItem], limit: Int? = nil) async throws
    -> [SubjectCatalogItem]
  {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let conversion = KanaConverter.convert(query)
    let kana = conversion.text
    var matches: [(item: SubjectCatalogItem, rank: Int)] = []
    for item in items {
      try Task.checkCancellation()
      let subject = item.subject
      guard level == 0 || subject.level == level, kind == nil || subject.kind == kind,
        scope.contains(item)
      else { continue }
      let meanings = subject.meanings.map { $0.text.lowercased() }
      let readings = subject.readings.map(\.text)
      let prefix =
        query.isEmpty || subject.japanese.hasPrefix(query)
        || meanings.contains(where: { $0.hasPrefix(query) })
        || readings.contains(where: { $0.hasPrefix(kana) })
      guard
        prefix || subject.japanese.contains(query)
          || meanings.contains(where: { $0.contains(query) })
          || readings.contains(where: { $0.contains(kana) })
      else { continue }
      let exact =
        !query.isEmpty
        && (subject.japanese == query || meanings.contains(query)
          || conversion.convertedAllCharacters && readings.contains(kana))
      matches.append((item, exact ? 0 : prefix ? 1 : 2))
    }
    matches.sort {
      if $0.rank != $1.rank { return $0.rank < $1.rank }
      if $0.item.subject.level != $1.item.subject.level {
        return $0.item.subject.level < $1.item.subject.level
      }
      return $0.item.id < $1.item.id
    }
    return (limit.map { Array(matches.prefix(max(0, $0))) } ?? matches).map(\.item)
  }
}

public enum SubjectCatalogOrder: Sendable {
  case level, remaining, stage, results
  public func sorted(_ items: [SubjectCatalogItem], now: Date) -> [SubjectCatalogItem] {
    if case .results = self { return items }
    func rank(_ item: SubjectCatalogItem) -> Int {
      switch item.status {
      case .unassigned: return 1001
      case .pending: return 1002
      case .locked: return 1000
      case .lesson: return -1
      case .studying(let stage, let reviewAt, _):
        if case .remaining = self {
          if let reviewAt, reviewAt <= now { return -2 }
          return 100 - stage.rawValue
        }
        return stage.rawValue
      }
    }
    return items.sorted {
      let a = rank($0)
      let b = rank($1)
      if a != b { return a < b }
      if $0.subject.level != $1.subject.level { return $0.subject.level < $1.subject.level }
      return $0.id < $1.id
    }
  }
}
