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

typealias UserData = [String: Any]

enum ComplicationDataSource: Int, Sendable {
  case reviews = 0
  case level = 1
  case legacyCharacter = 2
}

/// Reads the extension's existing cache without sharing a mutable dictionary between callers.
struct WatchCompanionCache: Sendable {
  static let sharedInstance = WatchCompanionCache()
  static let sourceKey = "DataSource"
  private static let dataKey = "LastKnownData"
  private static let dataStaleLimit: TimeInterval = 60 * 60 * 2
  @MainActor private static var started = false

  struct Status: Sendable {
    let sentAt: Date?
    let staleAfter: Date?

    func isStale(at date: Date) -> Bool {
      staleAfter.map { $0 < date } ?? false
    }
  }

  var latestData: UserData? { UserDefaults.standard.dictionary(forKey: Self.dataKey) }
  var dataSource: ComplicationDataSource {
    ComplicationDataSource(rawValue: UserDefaults.standard.integer(forKey: Self.sourceKey))
      ?? .reviews
  }
  var status: Status { Self.status(for: latestData) }

  static func status(for data: UserData?) -> Status {
    let sentAt = (data?[WatchHelper.keySentAt] as? EpochTimeInt).map {
      Date(timeIntervalSince1970: TimeInterval($0))
    }
    let staleAfter: Date?
    if let sentAt, let nextReviewAt = data?[WatchHelper.keyNextReviewAt] as? EpochTimeInt {
      staleAfter = max(
        sentAt.addingTimeInterval(Self.dataStaleLimit),
        Date(timeIntervalSince1970: TimeInterval(nextReviewAt)))
    } else {
      staleAfter = nil
    }
    return Status(sentAt: sentAt, staleAfter: staleAfter)
  }

  private init() {}

  @MainActor static func start() {
    guard !started else { return }
    started = true
    WatchHelper.sharedInstance.awaitMessages { userInfo in
      guard !sharedInstance.isDataOutOfDate(userData: userInfo) else { return }
      UserDefaults.standard.set(userInfo, forKey: dataKey)
    }
  }

  private func isDataOutOfDate(userData: UserData?) -> Bool {
    guard let dataSentAt = userData?[WatchHelper.keySentAt] as? EpochTimeInt else { return true }
    let dataSent = Date(timeIntervalSince1970: TimeInterval(dataSentAt))
    return dataSent < Date().addingTimeInterval(-Self.dataStaleLimit)
  }
}
