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

typealias ClientDelegateCallback = ([String: Any]) -> Void
typealias EpochTimeInt = Int64

class WatchConnectionServerDelegate: NSObject, WCSessionDelegate {
  var activated: (@MainActor () -> Void)?
  func session(
    _: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    guard state == .activated, error == nil else { return }
    DispatchQueue.main.async { self.activated?() }
  }

  #if os(iOS)
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  #endif
}

class WatchConnectionClientDelegate: NSObject, WCSessionDelegate {
  let callback: ClientDelegateCallback

  init(_ callback: @escaping ClientDelegateCallback) {
    self.callback = callback
  }

  func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: Error?) {
    os_log("watch activationDidCompleteWith err=%{public}@", error?.localizedDescription ?? "none")
  }

  func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    #if os(watchOS)
      let server = CLKComplicationServer.sharedInstance()
      if let complications = server.activeComplications {
        for complication in complications {
          server.reloadTimeline(for: complication)
        }
      }
    #endif
    callback(userInfo)
  }

  #if os(iOS)
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}
  #endif
}

@objc class WatchHelper: NSObject {
  public static let keyReviewCount = "reviewCount"
  public static let keyReviewNextHourCount = "reviewHrCount"
  public static let keyReviewUpcomingHourlyCounts = "reviewHourly"
  public static let keyLevelCurrent = "level"
  public static let keyLevelLearned = "levelLearn"
  public static let keyLevelTotal = "levelTotal"
  public static let keyLevelHalf = "levelHalf"
  public static let keyNextReviewAt = "nextReview"
  public static let keySentAt = "sent"

  @objc public static let sharedInstance = WatchHelper()
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
  let serverDelegate = WatchConnectionServerDelegate()
  var clientDelegate: WatchConnectionClientDelegate?

  override convenience init() {
    self.init(session: WCSession.isSupported() ? WCSession.default : nil)
  }

  init(session: WCSession?) {
    self.session = session
    super.init()
    #if os(iOS)
      startServerSession()
    #endif
  }

  #if os(iOS)
    @objc func startServerSession() {
      serverDelegate.activated = { [weak self] in self?.companion.flush() }
      if let session = session {
        session.delegate = serverDelegate
        session.activate()
      }
    }

  #endif

  func awaitMessages(callback: @escaping ClientDelegateCallback) {
    clientDelegate = WatchConnectionClientDelegate(callback)
    if let session = session {
      session.delegate = clientDelegate
      session.activate()
    }
  }

}
