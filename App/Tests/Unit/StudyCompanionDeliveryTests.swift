import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@MainActor private final class CompanionProbe {
  var active = true
  private(set) var packets: [(StudyCompanionSnapshot, Date)] = []
  func send(_ value: StudyCompanionSnapshot, _ date: Date) -> Bool {
    guard active else { return false }
    packets.append((value, date))
    return true
  }
}

@MainActor struct StudyCompanionDeliveryTests {
  private let now = Date(timeIntervalSince1970: 10_000)
  private var source: StudyServiceSnapshot {
    .init(reviewDates: [now, now.addingTimeInterval(60)], onVacation: false)
  }
  @Test func theFirstPacketParticipatesInTheThirtySecondDuplicateWindow() {
    let probe = CompanionProbe()
    let delivery = StudyCompanionDelivery(send: probe.send)
    delivery.update(source, now: now)
    delivery.update(source, now: now.addingTimeInterval(1))
    delivery.update(source, now: now.addingTimeInterval(29.99))
    #expect(probe.packets.count == 1 && delivery.lastSentAt == now)
    delivery.update(source, now: now.addingTimeInterval(30))
    #expect(probe.packets.count == 2 && delivery.lastSentAt == now.addingTimeInterval(30))
  }
  @Test func changedDataAndClockRollbackAreNeverSuppressed() {
    let probe = CompanionProbe()
    let delivery = StudyCompanionDelivery(send: probe.send)
    delivery.update(source, now: now)
    delivery.update(.init(), now: now.addingTimeInterval(1))
    delivery.update(.init(), now: now.addingTimeInterval(2))
    #expect(probe.packets.count == 2 && probe.packets.last?.0.reviews == 0)
    delivery.update(.init(), now: now.addingTimeInterval(-3600))
    #expect(probe.packets.count == 3)
  }
  @Test func anInactiveSessionRetainsOnlyTheLatestAccountSnapshot() {
    let probe = CompanionProbe()
    probe.active = false
    let delivery = StudyCompanionDelivery(send: probe.send)
    delivery.update(source, now: now)
    delivery.update(.init(), now: now.addingTimeInterval(1))
    #expect(
      delivery.pending?.onVacation == true && probe.packets.isEmpty && delivery.lastSentAt == nil)
    probe.active = true
    delivery.flush(now: now.addingTimeInterval(2))
    #expect(
      probe.packets.map(\.0) == [StudyCompanionSnapshot(.init(), now: now)]
        && delivery.pending == nil)
  }
  @Test func activationRecomputesCountsAndRelativeBinsFromAbsoluteDates() {
    let probe = CompanionProbe()
    probe.active = false
    let delivery = StudyCompanionDelivery(send: probe.send)
    delivery.update(source, now: now)
    probe.active = true
    let activatedAt = now.addingTimeInterval(61)
    delivery.flush(now: activatedAt)
    #expect(
      probe.packets.count == 1 && probe.packets[0].0.reviews == 2
        && probe.packets[0].0.upcoming.allSatisfy { $0 == 0 })
    #expect(probe.packets[0].0.nextReview == 0 && probe.packets[0].1 == activatedAt)
  }
  @Test func anUnsentValueDoesNotConsumeTheDuplicateWindow() {
    let probe = CompanionProbe()
    probe.active = false
    let delivery = StudyCompanionDelivery(send: probe.send)
    delivery.update(source, now: now)
    #expect(delivery.lastSentAt == nil)
    probe.active = true
    delivery.flush(now: now.addingTimeInterval(1))
    #expect(probe.packets.count == 1 && delivery.lastSentAt == now.addingTimeInterval(1))
    delivery.flush(now: now.addingTimeInterval(2))
    #expect(probe.packets.count == 1)
  }
}
