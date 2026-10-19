import Foundation
import StudyCore

/// The platform returns false until its session activates. Only the latest absolute schedule waits.
@MainActor public final class StudyCompanionDelivery {
  public private(set) var pending: StudyServiceSnapshot?
  public private(set) var lastSentAt: Date?
  private var lastSent: StudyCompanionSnapshot?
  private let send: @MainActor (StudyCompanionSnapshot, Date) -> Bool
  public init(send: @escaping @MainActor (StudyCompanionSnapshot, Date) -> Bool) {
    self.send = send
  }
  public func update(_ source: StudyServiceSnapshot, now: Date = .now) {
    pending = source
    flush(now: now)
  }
  public func flush(now: Date = .now) {
    guard let source = pending else { return }
    let value = StudyCompanionSnapshot(source, now: now)
    if value == lastSent, let lastSentAt, now >= lastSentAt,
      now < lastSentAt.addingTimeInterval(30)
    {
      pending = nil
      return
    }
    guard send(value, now) else { return }
    pending = nil
    lastSent = value
    lastSentAt = now
  }
}
