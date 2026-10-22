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
  import WatchKit
  import WidgetKit
#endif

#if os(watchOS)
  typealias ClientDelegateCallback = @MainActor @Sendable ([String: Any]) -> Void
#endif
typealias EpochTimeInt = Int64

/// WatchConnectivity calls on its own queue; the immutable callback returns to the UI actor.
#if os(iOS)
  final class WatchConnectionServerDelegate: NSObject, WCSessionDelegate, Sendable {
    private let activated: @MainActor @Sendable () -> Void
    private let review: @MainActor @Sendable (WatchReviewRequest) async -> WatchReviewResponse
    init(
      activated: @escaping @MainActor @Sendable () -> Void,
      review: @escaping @MainActor @Sendable (WatchReviewRequest) async -> WatchReviewResponse
    ) {
      self.activated = activated
      self.review = review
    }
    func session(_: WCSession, didReceiveMessageData data: Data) {
      guard data.count <= WatchReviewRequest.maximumMessageBytes,
        let request = try? PropertyListDecoder().decode(WatchReviewRequest.self, from: data)
      else { return }
      Task { @MainActor [review] in
        var response = await review(request)
        response.requestID = request.id
        WatchHelper.sharedInstance.sendReviewResponse(response)
      }
    }
    func session(
      _: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
    ) {
      guard state == .activated, error == nil else { return }
      Task { @MainActor [activated] in activated() }
    }
    func sessionDidBecomeInactive(_: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  }
#endif

#if os(watchOS)
  final class WatchConnectionClientDelegate: NSObject, WCSessionDelegate, Sendable {
    private let callback: ClientDelegateCallback
    private let packetCallbacks = DispatchGroup()

    var isProcessingPacket: Bool { packetCallbacks.wait(timeout: .now()) == .timedOut }

    init(_ callback: @escaping ClientDelegateCallback) {
      self.callback = callback
    }

    func session(_: WCSession, didReceiveMessageData data: Data) {
      Task { @MainActor in WatchHelper.sharedInstance.receiveReviewResponse(data) }
    }

    func session(
      _: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
    ) {
      os_log(
        "watch activationDidCompleteWith err=%{public}@", error?.localizedDescription ?? "none")
      let failed = error != nil || state != .activated
      Task { @MainActor in WatchHelper.sharedInstance.activationCompleted(failed: failed) }
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
      packetCallbacks.enter()
      DispatchQueue.main.async { [callback, packetCallbacks] in
        defer {
          packetCallbacks.leave()
          WatchHelper.sharedInstance.finishConnectivityTasks()
        }
        guard
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let userInfo = value as? [String: Any]
        else {
          os_log(.error, "Unable to decode WatchConnectivity property-list payload")
          return
        }
        callback(userInfo)
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
    var reviewRequest: (@MainActor @Sendable (WatchReviewRequest) async -> WatchReviewResponse)?
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
    private var contentObservation: NSKeyValueObservation?
    private var connectivityTasks: Set<WKWatchConnectivityRefreshBackgroundTask> = []
    private var activationFailed = false
    private var reviewReplies: [UUID: AsyncThrowingStream<Data, any Error>.Continuation] = [:]
  #endif

  init(session: WCSession?) {
    self.session = session
    #if os(iOS)
      startServerSession()
    #endif
  }

  #if os(iOS)
    func sendReviewResponse(_ value: WatchReviewResponse) {
      guard let session, session.activationState == .activated,
        let data = try? PropertyListEncoder().encode(value),
        data.count <= WatchReviewRequest.maximumMessageBytes
      else { return }
      session.sendMessageData(data, replyHandler: nil) { error in
        os_log(
          .error, "Watch review response could not be delivered: %{public}@",
          error.localizedDescription)
      }
    }

    func startServerSession() {
      let handler = WatchConnectionServerDelegate(
        activated: { [weak self] in self?.companion.flush() },
        review: { [weak self] request in
          await self?.reviewRequest?(request)
            ?? .init(
              runID: request.runID, outcome: .unavailable,
              feedback: "Open the app on your iPhone first.")
        })
      serverHandler = handler
      if let session = session {
        session.delegate = handler
        session.activate()
      }
    }

  #endif

  #if os(watchOS)
    func review(_ request: WatchReviewRequest) async throws -> WatchReviewResponse {
      guard let session else {
        throw WatchReviewError.message("Pair this Watch with your iPhone first.")
      }
      // A Watch message can wake the phone; an isReachable preflight would prevent that.
      for _ in 0..<50 {
        if session.activationState == .activated { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      guard session.activationState == .activated, session.isCompanionAppInstalled else {
        throw WatchReviewError.message("Open usagiunagi on your paired iPhone first.")
      }
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      let data = try encoder.encode(request)
      guard data.count <= WatchReviewRequest.maximumMessageBytes else {
        throw WatchReviewError.message("That answer was too long. Try a shorter answer.")
      }
      let (replies, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
      reviewReplies[request.id] = continuation
      let timeout = Task {
        do { try await Task.sleep(for: .seconds(25)) } catch { return }
        continuation.finish(
          throwing: WatchReviewError.message(
            "Your iPhone didn’t reply. Resume to reload the saved review."))
      }
      defer {
        reviewReplies[request.id] = nil
        timeout.cancel()
        continuation.finish()
      }
      session.sendMessageData(
        data, replyHandler: nil,
        errorHandler: { continuation.finish(throwing: $0) })
      for try await reply in replies {
        try Task.checkCancellation()
        guard reply.count <= WatchReviewRequest.maximumMessageBytes else {
          throw WatchReviewError.message("The phone sent an invalid review. Resume to reload it.")
        }
        let response = try PropertyListDecoder().decode(WatchReviewResponse.self, from: reply)
        guard response.runID == request.runID, response.requestID == request.id else {
          throw CancellationError()
        }
        return response
      }
      throw CancellationError()
    }

    func receiveReviewResponse(_ data: Data) {
      guard data.count <= WatchReviewRequest.maximumMessageBytes,
        let value = try? PropertyListDecoder().decode(WatchReviewResponse.self, from: data),
        let id = value.requestID, let reply = reviewReplies.removeValue(forKey: id)
      else { return }
      reply.yield(data)
      reply.finish()
    }

    func retainConnectivityTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
      connectivityTasks.insert(task)
      finishConnectivityTasks()
    }

    func activationCompleted(failed: Bool) {
      activationFailed = failed
      finishConnectivityTasks()
    }

    func finishConnectivityTasks() {
      if let session, !activationFailed {
        guard session.activationState == .activated, !session.hasContentPending else { return }
      }
      guard clientHandler?.isProcessingPacket != true else { return }
      let tasks = connectivityTasks
      connectivityTasks.removeAll()
      for task in tasks { task.setTaskCompletedWithSnapshot(false) }
    }

    @discardableResult static func reloadComplications() -> Bool {
      do {
        try WatchCompanionCache.sharedInstance.publish()
        WidgetCenter.shared.reloadTimelines(ofKind: WatchCompanionCache.widgetKind)
        return true
      } catch {
        os_log(
          .error, "Unable to publish the watch widget snapshot: %{public}@",
          error.localizedDescription)
        return false
      }
    }

    func awaitMessages(callback: @escaping ClientDelegateCallback) {
      clientHandler = WatchConnectionClientDelegate(callback)
      if let session = session {
        contentObservation = session.observe(\.hasContentPending, options: [.new]) {
          [weak self] _, _ in
          Task { @MainActor in self?.finishConnectivityTasks() }
        }
        session.delegate = clientHandler
        session.activate()
      }
    }
  #endif

}
