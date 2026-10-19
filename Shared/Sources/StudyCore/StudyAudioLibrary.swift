import Foundation
import Observation

public struct StudyAudioOptions: Codable, Equatable, Sendable {
  public var enabled = false
  public var cellular = false
  public var voiceIDs: Set<Int64> = []
  public init() {}
}

@MainActor public protocol StudyAudioPreferences: AnyObject {
  var options: StudyAudioOptions { get set }
}

@MainActor public final class DefaultsStudyAudioPreferences: StudyAudioPreferences {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public var options: StudyAudioOptions {
    get {
      var value = StudyAudioOptions()
      value.enabled = defaults.bool(forKey: "native.offlineAudio")
      value.cellular = defaults.bool(forKey: "native.offlineAudioCellular")
      value.voiceIDs = Set(
        (defaults.array(forKey: "native.offlineAudioVoices") as? [NSNumber] ?? []).map(\.int64Value)
      )
      return value
    }
    set {
      defaults.set(newValue.enabled, forKey: "native.offlineAudio")
      defaults.set(newValue.cellular, forKey: "native.offlineAudioCellular")
      defaults.set(
        newValue.voiceIDs.sorted().map(NSNumber.init(value:)), forKey: "native.offlineAudioVoices")
    }
  }
}

public struct StudyAudioCatalog: Equatable, Sendable {
  public let accountID: String
  public let currentLevel: Int
  public let maximumLevel: Int
  public let voices: [StudyVoiceActor]
  public let audio: [StudyAudioReference]
  public init(
    accountID: String, currentLevel: Int, maximumLevel: Int,
    voices: [StudyVoiceActor], audio: [StudyAudioReference]
  ) {
    self.accountID = accountID
    self.currentLevel = currentLevel
    self.maximumLevel = maximumLevel
    self.voices = voices.sorted { $0.id < $1.id }
    self.audio = audio.sorted {
      ($0.level, $0.subjectID, $0.voiceActorID) < ($1.level, $1.subjectID, $1.voiceActorID)
    }
  }
  public func downloads(for selectedVoices: Set<Int64>) -> [StudyAudioReference] {
    guard maximumLevel > 0 else { return [] }
    let current = min(max(1, currentLevel), maximumLevel)
    let levels =
      [current] + (1..<current).reversed() + (current < maximumLevel ? [current + 1] : [])
    let knownVoices = Set(voices.map(\.id)).intersection(selectedVoices)
    return levels.flatMap { level in
      audio.filter { $0.level == level && knownVoices.contains($0.voiceActorID) }
    }
  }
}

public enum OfflineAudioAction: Sendable {
  case enabled(Bool)
  case cellular(Bool)
  case voice(Int64, Bool)
  case retry, delete
}

/// One owner for pronunciation, downloaded files and voice preferences on every platform.
@MainActor @Observable public final class StudyAudioLibrary {
  public let downloads: StudyAudioDownloads
  public private(set) var options: StudyAudioOptions
  public private(set) var catalog: StudyAudioCatalog?
  public private(set) var subjectID: Int64?
  public var voices: [StudyVoiceActor] { catalog?.voices ?? [] }
  public var state: SubjectAudioState { playback.state }
  public var error: String? { selectionError ?? playback.error }
  private let preferences: any StudyAudioPreferences
  private let playback: any StudyAudioPlayback
  private var selectionError: String?
  private var lastIndex = 0
  private var voiceLeases: Set<UUID> = []
  public var voiceInputActive: Bool { !voiceLeases.isEmpty }
  public func beginVoiceInput() -> UUID {
    stop()
    let id = UUID()
    voiceLeases.insert(id)
    return id
  }
  public func endVoiceInput(_ id: UUID) {
    voiceLeases.remove(id)
    if voiceLeases.isEmpty { selectionError = nil }
  }

  public init(
    downloads: StudyAudioDownloads,
    preferences: any StudyAudioPreferences = DefaultsStudyAudioPreferences(),
    playback: (any StudyAudioPlayback)? = nil
  ) {
    self.downloads = downloads
    self.preferences = preferences
    self.playback = playback ?? AppleStudyAudioPlayback()
    options = preferences.options
  }
  public func updateCatalog(_ value: StudyAudioCatalog?) {
    let latest = preferences.options
    guard value == nil || catalog != value || latest != options else { return }
    if value == nil || catalog?.accountID != value?.accountID { stop() }
    catalog = value
    options = latest
    queueDownloads()
  }
  public func reloadPreferences() {
    let latest = preferences.options
    guard latest != options else { return }
    options = latest
    queueDownloads()
  }
  public func queueDownloads() {
    guard options.enabled, let catalog else {
      downloads.cancel()
      return
    }
    downloads.start(catalog.downloads(for: options.voiceIDs), allowsCellular: options.cellular)
  }
  public func send(_ action: OfflineAudioAction) {
    var value = preferences.options
    switch action {
    case .enabled(let enabled):
      value.enabled = enabled
      if enabled && value.voiceIDs.isEmpty { value.voiceIDs = Set(voices.map(\.id)) }
    case .cellular(let cellular): value.cellular = cellular
    case .voice(let id, let selected):
      if selected { value.voiceIDs.insert(id) } else { value.voiceIDs.remove(id) }
    case .retry: break
    case .delete: value.enabled = false
    }
    preferences.options = value
    options = value
    queueDownloads()
    if case .delete = action {
      stop()
      Task { await downloads.deleteAll() }
    }
  }
  public func play(subject: CatalogSubject, interruptBackgroundAudio: Bool = false) {
    guard !subject.audio.isEmpty else { return }
    guard !voiceInputActive else {
      subjectID = subject.id
      selectionError = "Finish or cancel voice input before playing pronunciation."
      return
    }
    stop()
    subjectID = subject.id
    lastIndex = (lastIndex + 1) % subject.audio.count
    var source = subject.audio[lastIndex]
    var url: URL?
    if downloads.isCached(subjectID: subject.id, voiceActorID: source.voiceActorID) {
      url = downloads.cacheURL(subjectID: subject.id, voiceActorID: source.voiceActorID)
    } else if let cached = subject.audio.enumerated().first(where: {
      downloads.isCached(subjectID: subject.id, voiceActorID: $0.element.voiceActorID)
    }) {
      lastIndex = cached.offset
      source = cached.element
      url = downloads.cacheURL(subjectID: subject.id, voiceActorID: source.voiceActorID)
    } else if let remote = URL(string: source.url), remote.scheme == "https", remote.host != nil,
      remote.user == nil, remote.password == nil
    {
      url = remote
    }
    guard let url else {
      selectionError = "This pronunciation URL is unavailable. Refresh the saved catalog."
      return
    }
    do { try playback.play(url: url, interruptBackgroundAudio: interruptBackgroundAudio) } catch {
      selectionError = error.localizedDescription
    }
  }
  public func toggle(subject: CatalogSubject, interruptBackgroundAudio: Bool = false) {
    if subjectID == subject.id && state != .idle {
      stop()
    } else {
      play(subject: subject, interruptBackgroundAudio: interruptBackgroundAudio)
    }
  }
  public func stop() {
    playback.stop()
    selectionError = nil
    subjectID = nil
  }
  public func state(for id: Int64) -> SubjectAudioState { subjectID == id ? state : .idle }
  public func error(for id: Int64) -> String? { subjectID == id ? error : nil }
}
