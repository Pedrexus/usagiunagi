import AVFoundation
import Foundation
import Observation

nonisolated public enum SubjectAudioState: Sendable { case idle, loading, playing }

@MainActor public protocol StudyAudioPlayback: AnyObject, Observable {
  var state: SubjectAudioState { get }
  var error: String? { get }
  func play(url: URL, interruptBackgroundAudio: Bool) throws
  func stop()
}

/// AVFoundation's native Observation support replaces manual KVO and UIKit alerts.
@MainActor @Observable public final class AppleStudyAudioPlayback: StudyAudioPlayback {
  private var player: AVPlayer?
  public private(set) var error: String?
  @ObservationIgnored private var completion: Task<Void, Never>?
  @ObservationIgnored private var monitoring: Task<Void, Never>?
  public init() {
    // Global AVFoundation opt-in must precede creation of every playback object.
    if !AVPlayer.isObservationEnabled { AVPlayer.isObservationEnabled = true }
  }
  isolated deinit { stop() }
  public var state: SubjectAudioState {
    guard let player else { return .idle }
    switch player.timeControlStatus {
    case .playing: return .playing
    case .waitingToPlayAtSpecifiedRate: return .loading
    case .paused: return player.currentItem?.status == .unknown ? .loading : .idle
    @unknown default: return .idle
    }
  }
  public func play(url: URL, interruptBackgroundAudio: Bool) throws {
    stop()
    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        options: interruptBackgroundAudio
          ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers] : [.mixWithOthers])
      try session.setActive(true)
    #endif
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    self.player = player
    let ended = NotificationCenter.default.notifications(
      named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
    completion = Task { [weak self] in
      for await _ in ended {
        guard !Task.isCancelled, self?.player === player else { return }
        self?.stop()
        return
      }
    }
    let changes = Observations { (item.status, player.status, player.timeControlStatus) }
    monitoring = Task { [weak self] in
      var played = false
      for await _ in changes {
        guard !Task.isCancelled, self?.player === player else { return }
        if item.status == .failed || player.status == .failed {
          let message =
            (item.error ?? player.error)?.localizedDescription ?? "Audio playback failed."
          self?.stop()
          self?.error = message
          return
        }
        if played && player.timeControlStatus == .paused {
          self?.stop()
          return
        }
        if player.timeControlStatus == .playing { played = true }
      }
    }
    player.play()
  }
  public func stop() {
    completion?.cancel()
    completion = nil
    monitoring?.cancel()
    monitoring = nil
    let previous = player
    player = nil
    previous?.pause()
    previous?.replaceCurrentItem(with: nil)
    #if os(iOS)
      if previous != nil {
        // Finish synchronously before voice capture can take ownership of the session.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }
    #endif
    error = nil
  }
}
