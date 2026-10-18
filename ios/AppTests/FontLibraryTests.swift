import CoreText
import Foundation
import StudyUI
import Synchronization
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor
struct FontLibraryTests {
  private func sources() throws -> URL {
    try #require(Bundle(for: FontFixtureBundle.self).resourceURL?.appendingPathComponent("fonts"))
  }

  @Test func originalCatalogFilesActivateAndGlyphChecksHandleUTF16() throws {
    let loader = FontLoader(
      directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      bundledFonts: try sources())
    #expect(loader.allFonts.map(\.fileName) == Font.fontDefinitions.map(\.fileName))
    for font in loader.allFonts { #expect(font.available, "\(font.fileName)") }
    let noto = try #require(loader.font(fileName: "noto-serif-jp.ttf"))
    #expect(noto.canRender("私自身"))
    #expect(noto.canRender("𠮟"))
    #expect(!noto.canRender("\u{10FFFF}"))
  }

  @Test func corruptFontFailsWithoutCrashing() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("not a font".utf8).write(to: file)
    #expect(Font.graphicsFont(path: file.path) == nil)
  }

  private func withLibrary(
    _ body: @MainActor (FontLoader, FontDownloadStub, URL, Data) async throws -> Void
  ) async throws {
    let previous = UserDefaults.standard.object(forKey: "selectedFonts")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("fonts")
    let definition = try #require(
      Font.fontDefinitions.first { $0.fileName == "sawarabi-mincho.ttf" })
    let data = try Data(contentsOf: sources().appendingPathComponent(definition.fileName))
    let stub = FontDownloadStub(data: data)
    defer {
      stub.remove()
      try? FileManager.default.removeItem(at: root)
      if let previous {
        UserDefaults.standard.set(previous, forKey: "selectedFonts")
      } else {
        UserDefaults.standard.removeObject(forKey: "selectedFonts")
      }
    }
    Settings.selectedFonts = ["other-font.ttf"]
    let loader = FontLoader(definitions: [definition], directory: directory, bundledFonts: nil)
    loader.allFonts[0].didDelete()
    try await body(loader, stub, directory.appendingPathComponent(definition.fileName), data)
  }

  private func waitFor(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !predicate(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(predicate())
  }

  @Test func downloadActivatesOnlyAfterSavingAndPreservesOtherChoices() async throws {
    try await withLibrary { loader, stub, file, data in
      let model = FontLibraryModel(loader: loader, configuration: stub.configuration)
      model.send(.download(file.lastPathComponent))
      #expect(model.options[0].progress != nil)
      try await waitFor { model.options[0].progress == nil }
      #expect(model.options[0].error == nil)
      #expect(model.options[0].fontName != nil)
      #expect(try Data(contentsOf: file) == data)
      #expect(Settings.selectedFonts == ["other-font.ttf", file.lastPathComponent])
      model.send(.select(file.lastPathComponent, false))
      #expect(Settings.selectedFonts == ["other-font.ttf"])
      model.send(.deleteAll)
      #expect(!FileManager.default.fileExists(atPath: file.path))
      #expect(Settings.selectedFonts.isEmpty && !model.canDelete && model.deletionError == nil)
    }
  }

  @Test(arguments: [404, 200])
  func invalidResponseCannotReplaceCacheOrSelectAndRetryCanRecover(_ status: Int) async throws {
    try await withLibrary { loader, stub, file, data in
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file)
      stub.update {
        $0.status = status
        $0.data = Data("invalid font response".utf8)
      }
      let model = FontLibraryModel(loader: loader, configuration: stub.configuration)
      model.send(.download(file.lastPathComponent))
      try await waitFor { model.options[0].progress == nil }
      #expect(model.options[0].error != nil)
      #expect(try Data(contentsOf: file) == data)
      #expect(Settings.selectedFonts == ["other-font.ttf"])
      stub.update {
        $0.status = 200
        $0.data = data
      }
      model.send(.download(file.lastPathComponent))
      try await waitFor { model.options[0].progress == nil }
      #expect(model.options[0].error == nil && model.options[0].fontName != nil)
      #expect(Settings.selectedFonts == ["other-font.ttf", file.lastPathComponent])
    }
  }

  @Test(arguments: [false, true])
  func cancellingOrDeletingStopsTheTaskWithoutSelectingIt(_ delete: Bool) async throws {
    try await withLibrary { loader, stub, file, _ in
      stub.update { $0.hold = true }
      let model = FontLibraryModel(loader: loader, configuration: stub.configuration)
      model.send(.download(file.lastPathComponent))
      try await waitFor { stub.state.started > 0 }
      model.send(delete ? .deleteAll : .cancel(file.lastPathComponent))
      try await waitFor { stub.state.stopped > 0 }
      #expect(model.options[0].progress == nil && model.options[0].error == nil)
      #expect(!FileManager.default.fileExists(atPath: file.path))
      #expect(Settings.selectedFonts == (delete ? [] : ["other-font.ttf"]))
    }
  }
}

private final class FontFixtureBundle: NSObject {}

private struct FontDownloadStub: Sendable {
  struct State: Sendable {
    var data: Data
    var status = 200
    var hold = false
    var started = 0
    var stopped = 0
  }
  static let states = Mutex<[String: State]>([:])
  let id = UUID().uuidString
  init(data: Data) { Self.states.withLock { $0[id] = State(data: data) } }
  var state: State { Self.states.withLock { $0[id]! } }
  func update(_ change: (inout State) -> Void) { Self.states.withLock { change(&$0[id]!) } }
  func remove() { Self.states.withLock { $0[id] = nil } }
  var configuration: URLSessionConfiguration {
    let value = URLSessionConfiguration.ephemeral
    value.protocolClasses = [FontDownloadProtocol.self]
    value.httpAdditionalHeaders = ["X-Font-Test": id]
    value.timeoutIntervalForResource = 4
    return value
  }
}

// URLSession owns each protocol instance; all mutable test state is protected by Mutex.
private final class FontDownloadProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let id = request.value(forHTTPHeaderField: "X-Font-Test"),
      let state = FontDownloadStub.states.withLock({ values -> FontDownloadStub.State? in
        values[id]?.started += 1
        return values[id]
      })
    else { return }
    if state.hold { return }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: state.status, httpVersion: nil,
      headerFields: ["Content-Length": "\(state.data.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: state.data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {
    if let id = request.value(forHTTPHeaderField: "X-Font-Test") {
      FontDownloadStub.states.withLock { $0[id]?.stopped += 1 }
    }
  }
}
