// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

enum ComplicationDataSource: Int, Codable, Sendable {
  case reviews = 0
  case level = 1
  case legacyCharacter = 2
}

/// The original phone packet; decoding never turns missing data into a verified zero.
struct WatchCompanionSnapshot: Codable, Sendable {
  let reviews: Int
  let nextHour: Int
  let hours: [Int]
  let level: Int
  let learned: Int
  let total: Int
  let halfLevel: Bool
  let nextReview: Int64
  let sent: Int64

  enum CodingKeys: String, CodingKey {
    case reviews = "reviewCount"
    case nextHour = "reviewHrCount"
    case hours = "reviewHourly"
    case level
    case learned = "levelLearn"
    case total = "levelTotal"
    case halfLevel = "levelHalf"
    case nextReview, sent
  }

  var sentAt: Date { Date(timeIntervalSince1970: TimeInterval(sent)) }
  var expiresAt: Date {
    max(sentAt.addingTimeInterval(7200), Date(timeIntervalSince1970: TimeInterval(nextReview)))
  }
  var levelLabel: String { halfLevel ? "\(level).5" : "\(level)" }
  var fraction: Double { total > 0 ? min(1, max(0, Double(learned) / Double(total))) : 0 }
  var remaining: Int { max(0, total - learned) }

  func reviewCounts(at date: Date) -> (due: Int, next: Int)? {
    guard date < expiresAt else { return nil }
    let horizon = min(24, hours.count)
    let elapsed = max(0, date.timeIntervalSince(sentAt)) / 3600
    let hour = Int(min(elapsed, Double(horizon)))
    var due = reviews
    for count in hours.prefix(hour) {
      let sum = due.addingReportingOverflow(count)
      guard !sum.overflow else { return nil }
      due = sum.partialValue
    }
    return (due, hour < horizon ? hours[hour] : 0)
  }

  func timelineDates(after date: Date) -> [Date] {
    guard expiresAt > date else { return [] }
    let dates = (0..<min(24, hours.count)).map {
      sentAt.addingTimeInterval(Double($0 + 1) * 3600)
    }.filter { $0 > date && $0 < expiresAt }
    return dates + [expiresAt]
  }

  static func decode(_ packet: [String: Any]) -> Self? {
    guard
      let data = try? PropertyListSerialization.data(
        fromPropertyList: packet, format: .binary, options: 0),
      let value = try? PropertyListDecoder().decode(Self.self, from: data),
      value.sent > 0, value.reviews >= 0, value.nextHour >= 0,
      value.level >= 0, value.learned >= 0, value.total >= 0,
      value.hours.allSatisfy({ $0 >= 0 })
    else { return nil }
    return value
  }
}

struct WatchCompanionState: Codable, Sendable {
  var sourceRawValue = ComplicationDataSource.reviews.rawValue
  var snapshot: WatchCompanionSnapshot?

  var source: ComplicationDataSource {
    ComplicationDataSource(rawValue: sourceRawValue) ?? .reviews
  }
}

/// Mirrors the installed extension's defaults into one atomic, read-only widget snapshot.
struct WatchCompanionCache: Sendable {
  static let sharedInstance = WatchCompanionCache()
  static let sourceKey = "DataSource"
  static let widgetKind = "StudyComplication"
  private static let dataKey = "LastKnownData"

  enum CacheError: Error { case sharedContainerUnavailable }

  var state: WatchCompanionState {
    WatchCompanionState(
      sourceRawValue: UserDefaults.standard.integer(forKey: Self.sourceKey),
      snapshot: UserDefaults.standard.dictionary(forKey: Self.dataKey)
        .flatMap(WatchCompanionSnapshot.decode))
  }

  static func widgetState() -> WatchCompanionState {
    guard let url = snapshotURL, let data = try? Data(contentsOf: url),
      let value = try? PropertyListDecoder().decode(WatchCompanionState.self, from: data)
    else { return WatchCompanionState() }
    return value
  }

  func receive(_ packet: [String: Any], at date: Date = .now) -> Bool {
    guard let snapshot = WatchCompanionSnapshot.decode(packet),
      snapshot.sentAt >= date.addingTimeInterval(-7200)
    else { return false }
    UserDefaults.standard.set(packet, forKey: Self.dataKey)
    return true
  }

  func publish() throws {
    guard let url = Self.snapshotURL else { throw CacheError.sharedContainerUnavailable }
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(state).write(to: url, options: .atomic)
  }

  private static var snapshotURL: URL? {
    guard
      let group = Bundle.main.object(forInfoDictionaryKey: "UsagiUnagiWatchAppGroup") as? String,
      group.hasPrefix("group.")
    else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("study-complication.plist")
  }
}
