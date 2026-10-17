/// Completed-subject results, separate from attempt accuracy and the upload queue.
public struct StudySessionSummary: Sendable {
  public struct Entry: Identifiable, Sendable {
    public let id: Int
    public let subject: StudySubject?
    public let level: Int
    public let meaningWrong: Bool
    public let readingWrong: Bool
    public var correct: Bool { !meaningWrong && !readingWrong }
    public init(id: Int, subject: StudySubject?, level: Int, meaningWrong: Bool, readingWrong: Bool)
    {
      self.id = id
      self.subject = subject
      self.level = level
      self.meaningWrong = meaningWrong
      self.readingWrong = readingWrong
    }
  }
  public struct Group: Identifiable, Sendable {
    public let id: Int
    public let entries: [Entry]
  }
  public let entries: [Entry]
  public let currentLevel: Int?
  public init(entries: [Entry], currentLevel: Int? = nil) {
    self.entries = entries
    self.currentLevel = currentLevel
  }
  public var correctCount: Int { entries.filter(\.correct).count }
  public var accuracy: Int? {
    entries.isEmpty ? nil : Int(Double(correctCount) / Double(entries.count) * 100)
  }
  public var missedGroups: [Group] {
    let groups = Dictionary(grouping: entries.filter { !$0.correct }, by: \.level)
    return groups.keys.sorted(by: >).map { Group(id: $0, entries: groups[$0]!) }
  }
}
