import Foundation
import StudyCore
import StudyUI
import Testing

@MainActor struct StudyCompanionDeliveryTests {
  private let now = Date(timeIntervalSince1970: 10_000)
  private var source: StudyServiceSnapshot {
    .init(reviewDates: [now, now.addingTimeInterval(60)], onVacation: false)
  }
  @Test func theFirstPacketParticipatesInTheThirtySecondDuplicateWindow() {
    var sent: [StudyCompanionSnapshot] = []
    let delivery = StudyCompanionDelivery { value, _ in
      sent.append(value)
      return true
    }
    delivery.update(source, now: now)
    delivery.update(source, now: now.addingTimeInterval(1))
    delivery.update(source, now: now.addingTimeInterval(29.99))
    #expect(sent.count == 1 && delivery.lastSentAt == now)
    delivery.update(source, now: now.addingTimeInterval(30))
    #expect(sent.count == 2 && delivery.lastSentAt == now.addingTimeInterval(30))
  }
  @Test func changedDataAndClockRollbackAreNeverSuppressed() {
    var sent: [StudyCompanionSnapshot] = []
    let delivery = StudyCompanionDelivery { value, _ in
      sent.append(value)
      return true
    }
    delivery.update(source, now: now)
    delivery.update(.init(), now: now.addingTimeInterval(1))
    delivery.update(.init(), now: now.addingTimeInterval(2))
    #expect(sent.count == 2 && sent.last?.reviews == 0)
    delivery.update(.init(), now: now.addingTimeInterval(-3600))
    #expect(sent.count == 3)
  }
  @Test func anInactiveSessionRetainsOnlyTheLatestAccountSnapshot() {
    var active = false
    var sent: [StudyCompanionSnapshot] = []
    let delivery = StudyCompanionDelivery { value, _ in
      guard active else { return false }
      sent.append(value)
      return true
    }
    delivery.update(source, now: now)
    delivery.update(.init(), now: now.addingTimeInterval(1))
    #expect(delivery.pending?.onVacation == true && sent.isEmpty && delivery.lastSentAt == nil)
    active = true
    delivery.flush(now: now.addingTimeInterval(2))
    #expect(sent == [StudyCompanionSnapshot(.init(), now: now)] && delivery.pending == nil)
  }
  @Test func activationRecomputesCountsAndRelativeBinsFromAbsoluteDates() {
    var active = false
    var sent: [(StudyCompanionSnapshot, Date)] = []
    let delivery = StudyCompanionDelivery { value, date in
      guard active else { return false }
      sent.append((value, date))
      return true
    }
    delivery.update(source, now: now)
    active = true
    let activatedAt = now.addingTimeInterval(61)
    delivery.flush(now: activatedAt)
    #expect(sent.count == 1 && sent[0].0.reviews == 2 && sent[0].0.upcoming.allSatisfy { $0 == 0 })
    #expect(sent[0].0.nextReview == 0 && sent[0].1 == activatedAt)
  }
  @Test func anUnsentValueDoesNotConsumeTheDuplicateWindow() {
    var active = false
    var sent = 0
    let delivery = StudyCompanionDelivery { _, _ in
      guard active else { return false }
      sent += 1
      return true
    }
    delivery.update(source, now: now)
    #expect(delivery.lastSentAt == nil)
    active = true
    delivery.flush(now: now.addingTimeInterval(1))
    #expect(sent == 1 && delivery.lastSentAt == now.addingTimeInterval(1))
    delivery.flush(now: now.addingTimeInterval(2))
    #expect(sent == 1)
  }
}
