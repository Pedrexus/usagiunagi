import Foundation
import Observation
import StudyCore

/// File downloads owned by the app, with the legacy subject/voice cache names.
@MainActor @Observable public final class StudyAudioDownloads {
  public enum Status: Sendable { case idle, preparing, downloading, finished, cancelled }
  public private(set) var status = Status.idle
  public private(set) var progress: Progress?
  public private(set) var failedFiles = 0
  public private(set) var cachedBytes: Int64?
  public private(set) var error: String?
  public private(set) var isDeleting = false
  public nonisolated let directory: URL
  @ObservationIgnored private let configuration: URLSessionConfiguration
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var revision = 0

  public init(directory: URL, configuration: URLSessionConfiguration = .default) {
    self.directory = directory
    self.configuration = configuration
  }
  deinit { work?.cancel() }

  public nonisolated func cacheURL(subjectID: Int64, voiceActorID: Int64) -> URL {
    directory.appendingPathComponent("a\(subjectID)-\(voiceActorID).mp3")
  }
  public nonisolated func isCached(subjectID: Int64, voiceActorID: Int64) -> Bool {
    Self.isUsable(cacheURL(subjectID: subjectID, voiceActorID: voiceActorID))
  }
  private nonisolated static func isUsable(_ file: URL) -> Bool {
    ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
  }

  public func start(_ assets: [StudyAudioReference], allowsCellular: Bool) {
    guard !isDeleting else { return }
    cancel()
    let revision = revision
    let directory = directory
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.allowsCellularAccess = allowsCellular
    configuration.waitsForConnectivity = true
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    let session = URLSession(configuration: configuration)
    let progress = Progress(totalUnitCount: -1)
    self.progress = progress
    failedFiles = 0
    error = nil
    status = .preparing
    work = Task { [weak self] in
      defer { session.invalidateAndCancel() }
      let pending = await Task.detached(priority: .utility) {
        var seen = Set<URL>()
        return assets.filter {
          let path = directory.appendingPathComponent("a\($0.subjectID)-\($0.voiceActorID).mp3")
          return seen.insert(path).inserted && !Self.isUsable(path)
        }
      }.value
      guard !Task.isCancelled, self?.revision == revision else { return }
      progress.totalUnitCount = Int64(pending.count)
      self?.status = .downloading
      let transfer: @MainActor @Sendable (StudyAudioReference) async -> Void = {
        [weak self] asset in
        guard !Task.isCancelled else { return }

        do {
          guard let url = URL(string: asset.url), url.scheme == "https", url.host != nil,
            url.user == nil, url.password == nil
          else { throw URLError(.badURL) }
          let (temporary, response) = try await session.download(from: url)
          defer { try? FileManager.default.removeItem(at: temporary) }
          try Task.checkCancellation()
          guard let owner = self, owner.revision == revision else { return }
          guard let response = response as? HTTPURLResponse, response.statusCode == 200,
            response.mimeType?.lowercased().hasPrefix("audio/") == true
              || response.mimeType?.lowercased() == "application/octet-stream",
            (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0
          else { throw URLError(.badServerResponse) }
          try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
          let destination = owner.cacheURL(
            subjectID: asset.subjectID, voiceActorID: asset.voiceActorID)
          if !Self.isUsable(destination) {
            if FileManager.default.fileExists(atPath: destination.path) {
              _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
              try FileManager.default.moveItem(at: temporary, to: destination)
            }
          }
        } catch {
          guard !Task.isCancelled, let owner = self, owner.revision == revision else {
            return
          }
          owner.failedFiles += 1
          owner.error = error.localizedDescription
        }
        guard !Task.isCancelled, self?.revision == revision else { return }
        self?.progress?.completedUnitCount += 1
      }
      var seenLevels = Set<Int>()
      let levels = pending.map(\.level).filter { seenLevels.insert($0).inserted }
      // Finish each priority level before starting another, with at most four active transfers.
      for level in levels {
        await withTaskGroup(of: Void.self) { group in
          for (index, asset) in pending.filter({ $0.level == level }).enumerated() {
            if index >= 4 { await group.next() }
            guard !Task.isCancelled, self?.revision == revision else {
              group.cancelAll()
              break
            }
            group.addTask { await transfer(asset) }
          }
        }
      }
      guard self?.revision == revision else { return }
      self?.status = .finished
      self?.work = nil
      await self?.refreshCacheSize()
    }
  }

  public func cancel() {
    revision += 1
    work?.cancel()
    work = nil
    progress?.cancel()
    status = .cancelled
  }

  public func refreshCacheSize() async {
    let directory = directory
    let revision = revision
    do {
      let size = try await Task.detached(priority: .utility) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return Int64(0) }
        let urls = try FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: [.fileAllocatedSizeKey])
        return try urls.reduce(Int64(0)) {
          $0 + Int64(try $1.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize ?? 0)
        }
      }.value
      if self.revision == revision { cachedBytes = size }
    } catch {
      if self.revision == revision { self.error = error.localizedDescription }
    }
  }

  public func deleteAll() async {
    guard !isDeleting else { return }
    cancel()
    isDeleting = true
    defer {
      revision += 1
      isDeleting = false
    }
    let directory = directory
    do {
      try await Task.detached(priority: .utility) {
        if FileManager.default.fileExists(atPath: directory.path) {
          try FileManager.default.removeItem(at: directory)
        }
      }.value
      cachedBytes = 0
      failedFiles = 0
      error = nil
      status = .idle
    } catch { self.error = error.localizedDescription }
  }
}
