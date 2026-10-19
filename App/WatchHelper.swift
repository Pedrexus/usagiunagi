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

#if os(watchOS)
  import ClockKit
#endif

typealias ClientDelegateCallback = ([String: Any]) -> Void
typealias EpochTimeInt = Int64

class WatchConnectionServerDelegate: NSObject, WCSessionDelegate {
  var activated: (() -> Void)?
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
  private(set) var pendingPacket: [String: Any]?
  let serverDelegate = WatchConnectionServerDelegate()
  var clientDelegate: WatchConnectionClientDelegate?
  var lastPacketSignature: String?
  var lastPacketSentAt: Date?
  private let duplicatePacketWindow = TimeInterval(30)

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
      serverDelegate.activated = { [weak self] in self?.sendPendingPacket() }
      if let session = session {
        session.delegate = serverDelegate
        session.activate()
      }
    }

    @objc func updatedData(client: LocalCachingClient?) {
      let onVacation = client?.getUserInfo()?.hasVacationStartedAt != false
      let upcoming = onVacation ? [] : client?.upcomingReviews ?? []
      var halfLevel = false
      var assignmentsAtCurrentLevel = client?.getAssignmentsAtUsersCurrentLevel() ?? []
      var learnedCount = assignmentsAtCurrentLevel.filter { assignment -> Bool in
        assignment.srsStage >= .guru1
      }.count

      // If the user is in the vocab and technically levels up but has 0
      // learned treat it as the prior level and set halfLevel=true
      if learnedCount == 0,
        let assignment = assignmentsAtCurrentLevel.first,
        assignment.level > 0
      {
        halfLevel = true
        assignmentsAtCurrentLevel = client?.getAssignments(level: Int(assignment.level) - 1) ?? []
        learnedCount =
          assignmentsAtCurrentLevel.filter { assignment -> Bool in
            assignment.srsStage >= .guru1
          }.count
      }

      let now = Int(Date().timeIntervalSince1970)
      let nextReviewEpoch: EpochTimeInt =
        onVacation
        ? 0
        : client?.getAllAssignments()
          .filter { a in a.isReviewStage && a.availableAt > now }
          .map { a in EpochTimeInt(a.availableAt) }
          .min() ?? 0

      let packet: [String: Any] = [
        WatchHelper.keyReviewCount: onVacation ? 0 : client?.availableReviewCount ?? 0,
        WatchHelper.keyReviewNextHourCount: upcoming.first ?? 0,
        WatchHelper.keyReviewUpcomingHourlyCounts: upcoming,
        WatchHelper.keyLevelCurrent: assignmentsAtCurrentLevel.first?.level ?? 0,
        WatchHelper.keyLevelTotal: assignmentsAtCurrentLevel.count,
        WatchHelper.keyLevelLearned: learnedCount,
        WatchHelper.keyLevelHalf: halfLevel,
        WatchHelper.keyNextReviewAt: nextReviewEpoch,
      ]

      pendingPacket = packet
      sendPendingPacket()
    }

    private func sendPendingPacket() {
      guard let session, session.activationState == .activated, let packet = pendingPacket else {
        return
      }
      pendingPacket = nil
      guard shouldSendPacket(packet: packet) else { return }
      session.transferCurrentComplicationUserInfo(
        packet.merging(
          [WatchHelper.keySentAt: EpochTimeInt(Date().timeIntervalSince1970)],
          uniquingKeysWith: { current, _ in current }))
    }
  #endif

  func awaitMessages(callback: @escaping ClientDelegateCallback) {
    clientDelegate = WatchConnectionClientDelegate(callback)
    if let session = session {
      session.delegate = clientDelegate
      session.activate()
    }
  }

  func packetSignature(packet: [String: Any]) -> String {
    var signature = ""
    for key in packet.keys.sorted() {
      signature += "\(key):\(packet[key] ?? "nil"),"
    }
    return signature
  }

  func shouldSendPacket(packet: [String: Any], now: Date = .now) -> Bool {
    let signature = packetSignature(packet: packet)
    if let lastSent = lastPacketSentAt, signature == lastPacketSignature,
      now >= lastSent, now < lastSent.addingTimeInterval(duplicatePacketWindow)
    {
      return false
    }
    lastPacketSignature = signature
    lastPacketSentAt = now
    return true
  }

}
