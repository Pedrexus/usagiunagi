import Foundation

public struct StudyLevelProgress: Identifiable, Sendable {
  public let kind: SubjectKind
  public private(set) var guru = 0
  public private(set) var apprentice = 0
  public private(set) var lessons = 0
  public private(set) var locked = 0
  public var id: SubjectKind { kind }
  public var total: Int { guru + apprentice + lessons + locked }
  public init(kind: SubjectKind, stages: [(stage: Int?, started: Bool)]) {
    self.kind = kind
    for item in stages {
      guard let stage = item.stage else {
        locked += 1
        continue
      }
      if stage == 0 && !item.started {
        lessons += 1
      } else if stage < 5 {
        apprentice += 1
      } else {
        guru += 1
      }
    }
  }
}
