import Foundation
import Observation

@MainActor public protocol StudyFontPreferences: AnyObject {
  var selectedFiles: Set<String> { get set }
}

@MainActor public final class DefaultsStudyFontPreferences: StudyFontPreferences {
  private let defaults: UserDefaults
  private let key: String
  private let changed: (@MainActor (Set<String>, Set<String>) -> Void)?
  public init(
    defaults: UserDefaults = .standard, key: String = "native.selectedFonts",
    changed: (@MainActor (Set<String>, Set<String>) -> Void)? = nil
  ) {
    self.defaults = defaults
    self.key = key
    self.changed = changed
  }
  public var selectedFiles: Set<String> {
    get { Set(defaults.stringArray(forKey: key) ?? []) }
    set {
      let old = selectedFiles
      defaults.set(newValue.sorted(), forKey: key)
      if old != newValue { changed?(old, newValue) }
    }
  }
}

nonisolated public struct StudyFontOption: Identifiable {
  public let id: String
  public let title: String
  public let previewText: String
  public let fontName: String?
  public let sizeBytes: Int64
  public let progress: Progress?
  public let error: String?
}

nonisolated public enum FontLibraryAction: Sendable {
  case download(String)
  case cancel(String)
  case select(String, Bool)
  case deleteAll
}

/// One app-owned catalog, download queue and durable selection for every font picker/review.
@MainActor @Observable public final class StudyFontLibrary {
  public private(set) var options: [StudyFontOption] = []
  public private(set) var selectedFiles: Set<String>
  public private(set) var canDelete = false
  public private(set) var deletionError: String?
  public let catalog: StudyFontCatalog
  @ObservationIgnored private let preferences: any StudyFontPreferences
  @ObservationIgnored private let session: URLSession
  @ObservationIgnored private var downloads: [String: Transfer] = [:]
  @ObservationIgnored private var errors: [String: String] = [:]
  private struct Transfer {
    let id: UUID
    let task: URLSessionDownloadTask
  }

  public init(
    catalog: StudyFontCatalog = .init(),
    preferences: any StudyFontPreferences = DefaultsStudyFontPreferences(),
    configuration: URLSessionConfiguration = .default
  ) {
    self.catalog = catalog
    self.preferences = preferences
    selectedFiles = preferences.selectedFiles
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    session = URLSession(configuration: configuration)
    refresh()
  }
  deinit { session.invalidateAndCancel() }

  public func reloadSelection() { selectedFiles = preferences.selectedFiles }

  public func fontNames(for text: String, excluding: [String] = []) -> [String] {
    guard !text.isEmpty else { return [] }
    var seen = Set(excluding)
    return catalog.allFonts.filter {
      selectedFiles.contains($0.fileName) && $0.canRender(text) && seen.insert($0.fontName).inserted
    }.map(\.fontName)
  }

  public func send(_ action: FontLibraryAction) {
    switch action {
    case .download(let file):
      guard catalog.font(fileName: file) != nil, downloads[file] == nil else { return }
      errors[file] = nil
      let id = UUID()
      let url = URL(string: "https://tsurukame.app/fonts/")!.appendingPathComponent(file)
      let task = session.downloadTask(with: url) { [weak self] location, response, error in
        let result = Self.stage(location, response: response, error: error)
        Task { @MainActor [weak self] in
          if let self {
            self.complete(file: file, id: id, result: result)
          } else if case .success(let file) = result {
            try? FileManager.default.removeItem(at: file)
          }
        }
      }
      downloads[file] = Transfer(id: id, task: task)
      task.resume()
    case .cancel(let file): downloads.removeValue(forKey: file)?.task.cancel()
    case .select(let file, let selected): select(file, selected: selected)
    case .deleteAll:
      for transfer in downloads.values { transfer.task.cancel() }
      downloads.removeAll()
      do {
        if FileManager.default.fileExists(atPath: catalog.directory.path) {
          try FileManager.default.removeItem(at: catalog.directory)
        }
        preferences.selectedFiles = []
        selectedFiles = []
        for font in catalog.allFonts { font.didDelete() }
        errors.removeAll()
        deletionError = nil
      } catch { deletionError = error.localizedDescription }
    }
    refresh()
  }
  private func select(_ file: String, selected: Bool) {
    guard catalog.font(fileName: file)?.available == true else { return }
    var current = preferences.selectedFiles
    if selected { current.insert(file) } else { current.remove(file) }
    preferences.selectedFiles = current
    selectedFiles = current
  }
  private func complete(file: String, id: UUID, result: Result<URL, any Error>) {
    defer { if case .success(let file) = result { try? FileManager.default.removeItem(at: file) } }
    guard downloads[file]?.id == id, let font = catalog.font(fileName: file) else { return }
    do {
      let temporary = try result.get()
      try FileManager.default.createDirectory(
        at: catalog.directory, withIntermediateDirectories: true)
      let destination = catalog.directory.appendingPathComponent(file)
      if FileManager.default.fileExists(atPath: destination.path) {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try FileManager.default.moveItem(at: temporary, to: destination)
      }
      font.reload()
      guard font.available else { throw FontLibraryFailure.invalidFont }
      select(file, selected: true)
    } catch { errors[file] = error.localizedDescription }
    downloads[file] = nil
    refresh()
  }
  private func refresh() {
    canDelete = FileManager.default.fileExists(atPath: catalog.directory.path)
    options = catalog.allFonts.map {
      StudyFontOption(
        id: $0.fileName, title: $0.displayName, previewText: StudyFont.previewText,
        fontName: $0.available ? $0.fontName : nil, sizeBytes: $0.sizeBytes,
        progress: downloads[$0.fileName]?.task.progress, error: errors[$0.fileName])
    }
  }
  private nonisolated static func stage(
    _ location: URL?, response: URLResponse?, error: (any Error)?
  ) -> Result<URL, any Error> {
    Result {
      if let error { throw error }
      guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
      guard response.statusCode == 200 else { throw FontLibraryFailure.http(response.statusCode) }
      guard let location, !StudyFont.fontNames(at: location).isEmpty else {
        throw FontLibraryFailure.invalidFont
      }
      // URLSession removes its temporary file after this callback; stage it before the actor hop.
      let file = FileManager.default.temporaryDirectory.appendingPathComponent(
        "font-\(UUID().uuidString)")
      try FileManager.default.moveItem(at: location, to: file)
      return file
    }
  }
}

nonisolated private enum FontLibraryFailure: LocalizedError {
  case invalidFont
  case http(Int)
  var errorDescription: String? {
    switch self {
    case .invalidFont:
      "The downloaded file could not be activated as a font. Try downloading it again."
    case .http(let status): "The font server returned HTTP \(status). Try again later."
    }
  }
}
