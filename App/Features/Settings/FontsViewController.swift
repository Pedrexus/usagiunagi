// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import Observation
import StudyUI
import SwiftUI
import UIKit

/// The scene keeps existing navigation callers; all font controls render in SwiftUI.
final class FontsViewController: UIHostingController<FontLibraryContent?> {
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices) { rootView = FontLibraryContent(model: services.fontLibrary) }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    title = "Select Fonts"
    navigationController?.setNavigationBarHidden(false, animated: animated)
  }
}

struct FontLibraryContent: View {
  @Bindable var model: FontLibraryModel
  @ArchivedPreference(Settings.$selectedFonts) private var selected: Set<String>
  var body: some View {
    FontLibraryView(
      options: model.options, selected: selected, canDelete: model.canDelete,
      deletionError: model.deletionError, action: model.send)
  }
}

/// Owned by services so downloads continue when the picker is closed.
@MainActor @Observable final class FontLibraryModel {
  private(set) var options: [StudyFontOption] = []
  private(set) var canDelete = false
  private(set) var deletionError: String?
  @ObservationIgnored private let loader: FontLoader
  @ObservationIgnored private var session: URLSession?
  @ObservationIgnored private var downloads: [String: URLSessionDownloadTask] = [:]
  @ObservationIgnored private var errors: [String: String] = [:]

  init(loader: FontLoader, configuration: URLSessionConfiguration = .default) {
    self.loader = loader
    session = URLSession(
      configuration: configuration,
      delegate: FontDownloadDelegate { [weak self] id, result in
        Task { @MainActor [weak self] in
          if let self {
            self.complete(id: id, result: result)
          } else if case .success(let file) = result {
            try? FileManager.default.removeItem(at: file)
          }
        }
      }, delegateQueue: nil)
    refresh()
  }

  deinit { session?.invalidateAndCancel() }

  func send(_ action: FontLibraryAction) {
    switch action {
    case .download(let file):
      guard loader.font(fileName: file) != nil, downloads[file] == nil, let session else { return }
      errors[file] = nil
      let task = session.downloadTask(
        with: URL(string: "https://tsurukame.app/fonts/")!.appendingPathComponent(file))
      downloads[file] = task
      task.resume()
    case .cancel(let file): downloads.removeValue(forKey: file)?.cancel()
    case .select(let file, let selected): select(file, selected: selected)
    case .deleteAll:
      for task in downloads.values { task.cancel() }
      downloads.removeAll()
      do {
        if FileManager.default.fileExists(atPath: loader.directory.path) {
          try FileManager.default.removeItem(at: loader.directory)
        }
        Settings.selectedFonts = []
        for font in loader.allFonts { font.didDelete() }
        errors.removeAll()
        deletionError = nil
      } catch { deletionError = error.localizedDescription }
    }
    refresh()
  }

  private func select(_ file: String, selected: Bool) {
    guard loader.font(fileName: file)?.available == true else { return }
    var current = Settings.selectedFonts
    if selected { current.insert(file) } else { current.remove(file) }
    Settings.selectedFonts = current
  }

  private func complete(id: Int, result: Result<URL, any Error>) {
    defer { if case .success(let file) = result { try? FileManager.default.removeItem(at: file) } }
    guard let file = downloads.first(where: { $0.value.taskIdentifier == id })?.key,
      let font = loader.font(fileName: file)
    else { return }
    do {
      let temporary = try result.get()
      guard Font.graphicsFont(path: temporary.path) != nil else {
        throw FontLibraryFailure.invalidFont
      }
      try FileManager.default.createDirectory(
        at: loader.directory, withIntermediateDirectories: true)
      let destination = loader.directory.appendingPathComponent(file)
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
    canDelete = FileManager.default.fileExists(atPath: loader.directory.path)
    options = loader.allFonts.map {
      StudyFontOption(
        id: $0.fileName, title: $0.displayName, previewText: Font.fontPreviewText,
        fontName: $0.available ? $0.fontName : nil,
        preview: UIImage(named: $0.definition.fontName).map { Image(uiImage: $0) },
        sizeBytes: $0.sizeBytes, progress: downloads[$0.fileName]?.progress,
        error: errors[$0.fileName])
    }
  }
}

private enum FontLibraryFailure: LocalizedError {
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

private final class FontDownloadDelegate: NSObject, URLSessionDownloadDelegate {
  let completed: @Sendable (Int, Result<URL, any Error>) -> Void
  init(completed: @escaping @Sendable (Int, Result<URL, any Error>) -> Void) {
    self.completed = completed
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      guard let response = downloadTask.response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      guard response.statusCode == 200 else { throw FontLibraryFailure.http(response.statusCode) }
      // A download URL expires when this callback returns. Transfer ownership before hopping to UI.
      let staged = FileManager.default.temporaryDirectory.appendingPathComponent(
        "font-\(UUID().uuidString)")
      try FileManager.default.moveItem(at: location, to: staged)
      completed(downloadTask.taskIdentifier, .success(staged))
    } catch { completed(downloadTask.taskIdentifier, .failure(error)) }
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    if let error { completed(task.taskIdentifier, .failure(error)) }
  }
}
