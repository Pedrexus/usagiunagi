import Foundation
import Testing

struct WatchCompanionCacheTests {
  private let sent: Int64 = 100_000
  private var now: Date { Date(timeIntervalSince1970: TimeInterval(sent)) }

  private func packet(
    sent: Int64? = nil, reviews: Int = 3, hours: [Int] = [2, 4, 1],
    nextReview: Int64? = nil, learned: Int = 7, total: Int = 10
  ) -> [String: Any] {
    [
      "reviewCount": reviews, "reviewHrCount": hours.first ?? 0, "reviewHourly": hours,
      "level": 4, "levelLearn": learned, "levelTotal": total, "levelHalf": true,
      "nextReview": nextReview ?? self.sent + 10_800, "sent": sent ?? self.sent,
    ]
  }

  @Test func completePacketRoundTripsEveryOriginalWireField() throws {
    let value = try #require(WatchCompanionSnapshot.decode(packet()))
    #expect(value.reviews == 3 && value.nextHour == 2 && value.hours == [2, 4, 1])
    #expect(value.level == 4 && value.learned == 7 && value.total == 10 && value.halfLevel)
    #expect(value.sent == sent && value.nextReview == sent + 10_800)
    let encoded = try PropertyListEncoder().encode(value)
    let wire = try #require(
      PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
    #expect(Set(wire.keys) == Set(packet().keys))
    #expect(wire["reviewCount"] as? Int == 3 && wire["reviewHrCount"] as? Int == 2)
    #expect(wire["reviewHourly"] as? [Int] == [2, 4, 1] && wire["levelHalf"] as? Bool == true)
    #expect(wire["sent"] as? Int64 == sent && wire["nextReview"] as? Int64 == sent + 10_800)
    #expect(try PropertyListDecoder().decode(WatchCompanionSnapshot.self, from: encoded) == value)
  }

  @Test func partialMistypedAndNegativePacketsNeverInventZeroData() {
    for key in packet().keys {
      var missing = packet()
      missing.removeValue(forKey: key)
      #expect(WatchCompanionSnapshot.decode(missing) == nil, "Missing \(key)")
      var mistyped = packet()
      mistyped[key] = "invalid"
      #expect(WatchCompanionSnapshot.decode(mistyped) == nil, "Mistyped \(key)")
    }
    for key in ["sent", "reviewCount", "reviewHrCount", "level", "levelLearn", "levelTotal"] {
      var negative = packet()
      negative[key] = -1
      #expect(WatchCompanionSnapshot.decode(negative) == nil, "Negative \(key)")
    }
    var zeroSent = packet()
    zeroSent["sent"] = 0
    #expect(WatchCompanionSnapshot.decode(zeroSent) == nil)
    var negativeHour = packet()
    negativeHour["reviewHourly"] = [0, -1]
    #expect(WatchCompanionSnapshot.decode(negativeHour) == nil)
    var nonPropertyList = packet()
    nonPropertyList["unsupported"] = NSObject()
    #expect(WatchCompanionSnapshot.decode(nonPropertyList) == nil)
  }

  @Test func validZeroAndHalfLevelHaveTheirOwnMeaning() throws {
    let zero = try #require(
      WatchCompanionSnapshot.decode(
        packet(reviews: 0, hours: [], nextReview: 0, learned: 0, total: 0)))
    #expect(zero.reviews == 0 && zero.nextHour == 0 && zero.hours.isEmpty)
    #expect(zero.fraction == 0 && zero.remaining == 0 && zero.levelLabel == "4.5")
    #expect(zero.expiresAt == now.addingTimeInterval(7200))
    let beyondTotal = try #require(WatchCompanionSnapshot.decode(packet(learned: 12)))
    #expect(beyondTotal.fraction == 1 && beyondTotal.remaining == 0)
    let normal = try #require(WatchCompanionSnapshot.decode(packet()))
    #expect(normal.fraction == 0.7 && normal.remaining == 3)
  }

  @Test func exactTwoHourReceiveCutoffPreservesRejectedPacketState() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let boundary = now.addingTimeInterval(7200)
    #expect(fixture.cache.receive(packet(), at: boundary))
    let accepted = fixture.cache.state
    let bytes = try PropertyListSerialization.data(
      fromPropertyList: fixture.defaults.dictionary(forKey: "LastKnownData") ?? [:],
      format: .binary, options: 0)
    #expect(!fixture.cache.receive(packet(reviews: 99), at: boundary.addingTimeInterval(1)))
    #expect(!fixture.cache.receive(["sent": sent], at: boundary))
    #expect(fixture.cache.state == accepted)
    let preserved = try PropertyListSerialization.data(
      fromPropertyList: fixture.defaults.dictionary(forKey: "LastKnownData") ?? [:],
      format: .binary, options: 0)
    #expect(bytes == preserved)
    let zero = try #require(WatchCompanionSnapshot.decode(packet(hours: [], nextReview: 0)))
    #expect(zero.reviewCounts(at: boundary) == nil)
  }

  @Test func validClockCorrectionAndOutOfOrderDeliveryRetainOriginalAgeOnlyPolicy() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    #expect(fixture.cache.receive(packet(sent: sent + 3600, reviews: 9), at: now))
    #expect(fixture.cache.receive(packet(reviews: 4), at: now))
    #expect(fixture.cache.state.snapshot?.reviews == 4)
    #expect(fixture.cache.state.snapshot?.sent == sent)
    let corrected = now.addingTimeInterval(-3600)
    #expect(fixture.cache.receive(packet(sent: sent - 3600, reviews: 6), at: corrected))
    #expect(fixture.cache.state.snapshot?.sent == sent - 3600)
    #expect(fixture.cache.state.snapshot?.reviews == 6)
  }

  @Test func fullHourProjectionUsesIndependentBucketsAndExactExpiry() throws {
    let value = try #require(WatchCompanionSnapshot.decode(packet()))
    for (offset, due, next) in [
      (-1.0, 3, 2), (0, 3, 2), (3599.999, 3, 2), (3600, 5, 4),
      (7199.999, 5, 4), (7200, 9, 1), (10_799.999, 9, 1),
    ] {
      let counts = try #require(value.reviewCounts(at: now.addingTimeInterval(offset)))
      #expect(counts.due == due && counts.next == next, "Offset \(offset)")
    }
    #expect(value.reviewCounts(at: now.addingTimeInterval(10_800)) == nil)
    #expect(value.reviewCounts(at: now.addingTimeInterval(10_801)) == nil)
    #expect(value.timelineDates(after: now) == [3600, 7200, 10_800].map(now.addingTimeInterval))
    #expect(
      value.timelineDates(after: now.addingTimeInterval(3600))
        == [7200, 10_800].map(now.addingTimeInterval))
    #expect(value.timelineDates(after: value.expiresAt).isEmpty)
  }

  @Test func forecastStopsAtTwentyFourBucketsAndRetainsLaterExpiry() throws {
    let value = try #require(
      WatchCompanionSnapshot.decode(
        packet(hours: Array(repeating: 1, count: 30), nextReview: sent + 108_000)))
    let counts = try #require(value.reviewCounts(at: now.addingTimeInterval(90_000)))
    #expect(counts.due == 27 && counts.next == 0)
    let dates = value.timelineDates(after: now)
    #expect(dates.count == 25)
    #expect(dates.dropLast() == (1...24).map { now.addingTimeInterval(Double($0) * 3600) }[...])
    #expect(dates.last == now.addingTimeInterval(108_000))
    #expect(value.timelineDates(after: now.addingTimeInterval(90_000)) == [value.expiresAt])
    #expect(value.reviewCounts(at: value.expiresAt) == nil)
  }

  @Test func emptyAndVacationSchedulesStillEmitTheExactStaleMarker() throws {
    for nextReview in [Int64(0), sent + 1800, sent + 18_000] {
      let value = try #require(
        WatchCompanionSnapshot.decode(packet(reviews: 0, hours: [], nextReview: nextReview)))
      let counts = try #require(value.reviewCounts(at: now))
      #expect(counts.due == 0 && counts.next == 0)
      #expect(value.timelineDates(after: now) == [value.expiresAt])
      #expect(value.timelineDates(after: value.expiresAt).isEmpty)
    }
    let short = try #require(WatchCompanionSnapshot.decode(packet(nextReview: 0)))
    #expect(short.timelineDates(after: now) == [3600, 7200].map(now.addingTimeInterval))
  }

  @Test func overflowMakesForecastUnavailableWithoutChangingSavedCounts() throws {
    let value = try #require(
      WatchCompanionSnapshot.decode(packet(reviews: Int.max, hours: [1], nextReview: sent + 10_800))
    )
    let initial = try #require(value.reviewCounts(at: now))
    #expect(initial.due == Int.max && initial.next == 1)
    #expect(value.reviewCounts(at: now.addingTimeInterval(3600)) == nil)
    #expect(value.reviews == Int.max && value.hours == [1])
    let maximumLevel = try #require(
      WatchCompanionSnapshot.decode(packet(learned: 0, total: Int.max)))
    #expect(maximumLevel.remaining == Int.max && maximumLevel.fraction == 0)
  }

  @Test(arguments: [0, 1, 2, 99, -1])
  func rawSelectionAndCompletePrivatePacketSurviveMirrorRoundTrip(_ raw: Int) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.defaults.set(raw, forKey: WatchCompanionCache.sourceKey)
    var source = packet()
    source["historicalExtra"] = "retained privately"
    #expect(fixture.cache.receive(source, at: now))
    let expected = fixture.cache.state
    try fixture.cache.publish()
    let mirrored = WatchCompanionCache.widgetState(at: fixture.url)
    #expect(mirrored == expected && mirrored.sourceRawValue == raw)
    #expect(mirrored.source == (ComplicationDataSource(rawValue: raw) ?? .reviews))
    #expect(fixture.defaults.integer(forKey: "DataSource") == raw)
    #expect(
      fixture.defaults.dictionary(forKey: "LastKnownData")?["historicalExtra"] as? String
        == "retained privately")
    #expect(try Data(contentsOf: fixture.url).starts(with: Data("bplist00".utf8)))
    #expect(WatchCompanionCache.sourceKey == "DataSource")
    #expect(WatchCompanionCache.widgetKind == "StudyComplication")
  }

  @Test func startupBeforeFirstPacketMirrorsUnavailableWithoutInventingZero() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.defaults.set(2, forKey: "DataSource")
    #expect(fixture.cache.state.snapshot == nil)
    try fixture.cache.publish()
    let state = WatchCompanionCache.widgetState(at: fixture.url)
    #expect(state.sourceRawValue == 2 && state.source == .reviews && state.snapshot == nil)
    #expect(fixture.defaults.object(forKey: "LastKnownData") == nil)
    let zero = packet(reviews: 0, hours: [], nextReview: 0, learned: 0, total: 0)
    #expect(fixture.cache.receive(zero, at: now))
    try fixture.cache.publish()
    #expect(WatchCompanionCache.widgetState(at: fixture.url).snapshot?.reviews == 0)
  }

  @Test func absentAndUnreadableMirrorsAreUnavailableAndNeverRewritten() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    #expect(WatchCompanionCache.widgetState(at: nil).snapshot == nil)
    #expect(WatchCompanionCache.widgetState(at: fixture.url).snapshot == nil)
    let corrupt = Data("not a property list".utf8)
    try corrupt.write(to: fixture.url)
    #expect(WatchCompanionCache.widgetState(at: fixture.url).snapshot == nil)
    #expect(try Data(contentsOf: fixture.url) == corrupt)
    #expect(fixture.defaults.object(forKey: "LastKnownData") == nil)
  }

  @Test(arguments: [
    "sent", "reviewCount", "reviewHrCount", "level", "levelLearn", "levelTotal", "reviewHourly",
  ])
  func malformedNestedMirrorIsUnavailableAndKeepsRawSelection(_ key: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    var invalid = packet()
    if key == "reviewHourly" { invalid[key] = [0, -1] } else { invalid[key] = Int.min }
    invalid["levelTotal"] = Int.max
    if key == "levelTotal" { invalid[key] = Int.min }
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["sourceRawValue": 2, "snapshot": invalid], format: .binary, options: 0)
    try data.write(to: fixture.url)
    let state = WatchCompanionCache.widgetState(at: fixture.url)
    #expect(state.sourceRawValue == 2 && state.source == .reviews)
    #expect(state.snapshot == nil)
    #expect(try Data(contentsOf: fixture.url) == data)
    fixture.defaults.set(invalid, forKey: "LastKnownData")
    #expect(fixture.cache.state.snapshot == nil)
  }

  @Test func failedAtomicPublicationKeepsPriorMirrorAndPrivatePacket() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    #expect(fixture.cache.receive(packet(), at: now))
    try fixture.cache.publish()
    let original = try Data(contentsOf: fixture.url)
    #expect(fixture.cache.receive(packet(reviews: 42), at: now))
    fixture.defaults.set(1, forKey: "DataSource")
    let privateState = fixture.cache.state
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
    }
    #expect(throws: (any Error).self) { try fixture.cache.publish() }
    #expect(try Data(contentsOf: fixture.url) == original)
    #expect(fixture.cache.state == privateState && privateState.snapshot?.reviews == 42)
    #expect(WatchCompanionCache.widgetState(at: fixture.url).snapshot?.reviews == 3)
  }

  @Test func missingSharedContainerDoesNotErasePrivateState() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let unavailable = WatchCompanionCache(defaultsSuiteName: fixture.domain, mirrorURL: nil)
    #expect(unavailable.receive(packet(), at: now))
    let state = unavailable.state
    #expect(throws: WatchCompanionCache.CacheError.sharedContainerUnavailable) {
      try unavailable.publish()
    }
    #expect(unavailable.state == state && state.snapshot?.reviews == 3)
    #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
  }

  private struct Fixture {
    let domain = "WatchCompanionCacheTests.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let cache: WatchCompanionCache
    var url: URL { directory.appendingPathComponent("study-complication.plist") }

    init() throws {
      defaults = try #require(UserDefaults(suiteName: domain))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      cache = WatchCompanionCache(
        defaultsSuiteName: domain,
        mirrorURL: directory.appendingPathComponent("study-complication.plist"))
    }

    func remove() {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: directory)
    }
  }
}
