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
import WatchConnectivity
import os

#if os(iOS)
  import StudyCore
  import StudyUI
#endif

#if os(watchOS)
  import ClockKit
#endif

#if os(watchOS)
  typealias ClientDelegateCallback = @MainActor @Sendable ([String: Any]) -> Void
#endif
typealias EpochTimeInt = Int64

/// WatchConnectivity calls on its own queue; the immutable callback returns to the UI actor.
final class WatchConnectionServerDelegate: NSObject, WCSessionDelegate, Sendable {
  private let activated: @MainActor @Sendable () -> Void
  init(activated: @escaping @MainActor @Sendable () -> Void) { self.activated = activated }
  func session(
    _: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    guard state == .activated, error == nil else { return }
    Task { @MainActor [activated] in activated() }
  }
  #if os(iOS)
    func sessionDidBecomeInactive(_: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  #endif
}

#if os(watchOS)
  final class WatchConnectionClientDelegate: NSObject, WCSessionDelegate, Sendable {
    private let callback: ClientDelegateCallback

    init(_ callback: @escaping ClientDelegateCallback) {
      self.callback = callback
    }

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: Error?)
    {
      os_log(
        "watch activationDidCompleteWith err=%{public}@", error?.localizedDescription ?? "none")
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
      // Preserve property-list types and serial delivery without transferring Any across executors.
      guard
        let data = try? PropertyListSerialization.data(
          fromPropertyList: userInfo, format: .binary, options: 0)
      else {
        os_log(.error, "Unable to encode WatchConnectivity property-list payload")
        return
      }
      DispatchQueue.main.async { [callback] in
        guard
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let userInfo = value as? [String: Any]
        else {
          os_log(.error, "Unable to decode WatchConnectivity property-list payload")
          return
        }
        callback(userInfo)
        WatchHelper.reloadComplications()
      }
    }
  }

#endif

@MainActor final class WatchHelper {
  nonisolated public static let keyReviewCount = "reviewCount"
  nonisolated public static let keyReviewNextHourCount = "reviewHrCount"
  nonisolated public static let keyReviewUpcomingHourlyCounts = "reviewHourly"
  nonisolated public static let keyLevelCurrent = "level"
  nonisolated public static let keyLevelLearned = "levelLearn"
  nonisolated public static let keyLevelTotal = "levelTotal"
  nonisolated public static let keyLevelHalf = "levelHalf"
  nonisolated public static let keyNextReviewAt = "nextReview"
  nonisolated public static let keySentAt = "sent"

  static let sharedInstance = WatchHelper(
    session: WCSession.isSupported() ? WCSession.default : nil)
  private let session: WCSession?
  #if os(iOS)
    @MainActor private(set) lazy var companion = StudyCompanionDelivery { [weak self] value, date in
      guard let session = self?.session, session.activationState == .activated else { return false }
      session.transferCurrentComplicationUserInfo(
        Self.packet(value).merging(
          [Self.keySentAt: EpochTimeInt(date.timeIntervalSince1970)],
          uniquingKeysWith: { current, _ in current }))
      return true
    }
    @MainActor var pendingPacket: [String: Any]? {
      companion.pending.map { Self.packet(StudyCompanionSnapshot($0)) }
    }
    static func packet(_ value: StudyCompanionSnapshot) -> [String: Any] {
      [
        keyReviewCount: value.reviews, keyReviewNextHourCount: value.upcoming.first ?? 0,
        keyReviewUpcomingHourlyCounts: value.upcoming, keyLevelCurrent: value.level,
        keyLevelTotal: value.total, keyLevelLearned: value.learned, keyLevelHalf: value.halfLevel,
        keyNextReviewAt: value.nextReview,
      ]
    }
  #endif
  // WCSession.delegate is weak; retain the platform's handler for the whole session.
  #if os(iOS)
    private var serverHandler: WatchConnectionServerDelegate?
  #else
    private var clientHandler: WatchConnectionClientDelegate?
  #endif

  init(session: WCSession?) {
    self.session = session
    #if os(iOS)
      startServerSession()
    #endif
  }

  #if os(iOS)
    func startServerSession() {
      let handler = WatchConnectionServerDelegate { [weak self] in self?.companion.flush() }
      serverHandler = handler
      if let session = session {
        session.delegate = handler
        session.activate()
      }
    }

  #endif

  #if os(watchOS)
    static func reloadComplications() {
      let server = CLKComplicationServer.sharedInstance()
      for complication in server.activeComplications ?? [] {
        server.reloadTimeline(for: complication)
      }
    }

    func awaitMessages(callback: @escaping ClientDelegateCallback) {
      clientHandler = WatchConnectionClientDelegate(callback)
      if let session = session {
        session.delegate = clientHandler
        session.activate()
      }
    }
  #endif

}
