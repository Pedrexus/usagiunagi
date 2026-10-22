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
}

/// The original phone packet; decoding never turns missing data into a verified zero.
struct WatchCompanionSnapshot: Codable, Equatable, Sendable {
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

  fileprivate var isValid: Bool {
    sent > 0 && reviews >= 0 && nextHour >= 0 && level >= 0 && learned >= 0 && total >= 0
      && hours.allSatisfy { $0 >= 0 }
  }

  static func decode(_ packet: [String: Any]) -> Self? {
    guard
      let data = try? PropertyListSerialization.data(
        fromPropertyList: packet, format: .binary, options: 0),
      let value = try? PropertyListDecoder().decode(Self.self, from: data),
      value.isValid
    else { return nil }
    return value
  }
}

struct WatchCompanionState: Codable, Equatable, Sendable {
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

  private let defaultsSuiteName: String?
  private let mirrorURL: URL?

  init(defaultsSuiteName: String? = nil, mirrorURL: URL? = Self.snapshotURL) {
    self.defaultsSuiteName = defaultsSuiteName
    self.mirrorURL = mirrorURL
  }

  enum CacheError: Error { case defaultsUnavailable, sharedContainerUnavailable }

  private var defaults: UserDefaults? {
    if let defaultsSuiteName { UserDefaults(suiteName: defaultsSuiteName) } else { .standard }
  }

  var state: WatchCompanionState {
    guard let defaults else { return WatchCompanionState() }
    return WatchCompanionState(
      sourceRawValue: defaults.integer(forKey: Self.sourceKey),
      snapshot: defaults.dictionary(forKey: Self.dataKey)
        .flatMap(WatchCompanionSnapshot.decode))
  }

  static func widgetState(at url: URL? = snapshotURL) -> WatchCompanionState {
    guard let url, let data = try? Data(contentsOf: url),
      var value = try? PropertyListDecoder().decode(WatchCompanionState.self, from: data)
    else { return WatchCompanionState() }
    if let snapshot = value.snapshot, !snapshot.isValid { value.snapshot = nil }
    return value
  }

  func receive(_ packet: [String: Any], at date: Date = .now) -> Bool {
    guard let defaults, let snapshot = WatchCompanionSnapshot.decode(packet),
      snapshot.sentAt >= date.addingTimeInterval(-7200)
    else { return false }
    defaults.set(packet, forKey: Self.dataKey)
    return true
  }

  func publish() throws {
    guard defaults != nil else { throw CacheError.defaultsUnavailable }
    guard let url = mirrorURL else { throw CacheError.sharedContainerUnavailable }
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
