import CoreText
import Foundation
import Synchronization
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor
struct StudyFontLibraryTests {
  private func withLibrary(
    _ body:
      @MainActor (StudyFontCatalog, FontPreferencesFixture, FontDownloadStub, URL, Data)
      async throws -> Void
  ) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let directory = root.appending(path: "fonts")
    let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 24, nil)
    let source = try #require(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
    let data = try Data(contentsOf: source)
    let definition = StudyFontDefinition(
      "DownloadFixture-\(UUID().uuidString)", "fixture.ttf", "Fixture", Int64(data.count))
    let catalog = StudyFontCatalog(
      definitions: [definition], directory: directory, bundledFonts: nil)
    let preferences = FontPreferencesFixture(["other-font.ttf"])
    let stub = FontDownloadStub(data: data)
    defer {
      stub.remove()
      try? FileManager.default.removeItem(at: root)
    }
    try await body(catalog, preferences, stub, directory.appending(path: definition.fileName), data)
  }
  private func waitFor(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !predicate(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(predicate())
  }
  @Test func activationFollowsTheFileAndSelectionPreservesOtherChoices() async throws {
    try await withLibrary { catalog, preferences, stub, file, data in
      let library = StudyFontLibrary(
        catalog: catalog, preferences: preferences, configuration: stub.configuration)
      #expect(library.options[0].fontName == nil && library.fontNames(for: "私").isEmpty)
      library.send(.download(file.lastPathComponent))
      #expect(library.options[0].progress != nil)
      try await waitFor { library.options[0].progress == nil }
      #expect(library.options[0].error == nil && library.options[0].fontName != nil)
      #expect(try Data(contentsOf: file) == data)
      #expect(preferences.selectedFiles == ["other-font.ttf", file.lastPathComponent])
      #expect(
        library.fontNames(for: "私").count == 1,
        "Font: \(catalog.allFonts[0].fontName), available: \(catalog.allFonts[0].available), glyphs: \(catalog.allFonts[0].canRender("私")), selected: \(library.selectedFiles)"
      )
      #expect(library.fontNames(for: "").isEmpty && library.fontNames(for: "\u{10FFFF}").isEmpty)
      let names = library.fontNames(for: "私")
      #expect(library.fontNames(for: "私", excluding: names).isEmpty)
      preferences.selectedFiles.insert("new-choice.ttf")
      library.send(.select(file.lastPathComponent, false))
      #expect(library.selectedFiles == ["other-font.ttf", "new-choice.ttf"])
      library.send(.deleteAll)
      #expect(preferences.selectedFiles.isEmpty && library.selectedFiles.isEmpty)
      #expect(
        !FileManager.default.fileExists(atPath: file.path) && !library.canDelete
          && library.deletionError == nil)
    }
  }
  @Test(arguments: [404, 200])
  func badResponsesKeepPriorCacheAndCanRetry(status: Int) async throws {
    try await withLibrary { catalog, preferences, stub, file, data in
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file)
      stub.update {
        $0.status = status
        $0.data = Data("invalid font response".utf8)
      }
      let library = StudyFontLibrary(
        catalog: catalog, preferences: preferences, configuration: stub.configuration)
      library.send(.download(file.lastPathComponent))
      try await waitFor { library.options[0].progress == nil }
      #expect(library.options[0].error != nil && library.options[0].fontName == nil)
      #expect(try Data(contentsOf: file) == data)
      #expect(preferences.selectedFiles == ["other-font.ttf"])
      stub.update {
        $0.status = 200
        $0.data = data
      }
      library.send(.download(file.lastPathComponent))
      try await waitFor { library.options[0].progress == nil }
      #expect(library.options[0].error == nil && library.options[0].fontName != nil)
      #expect(preferences.selectedFiles == ["other-font.ttf", file.lastPathComponent])
    }
  }
  @Test(arguments: [false, true])
  func cancellationOrDeletionStopsTransfersWithoutSelecting(delete: Bool) async throws {
    try await withLibrary { catalog, preferences, stub, file, _ in
      stub.update { $0.hold = true }
      let library = StudyFontLibrary(
        catalog: catalog, preferences: preferences, configuration: stub.configuration)
      library.send(.download(file.lastPathComponent))
      try await waitFor { stub.state.started > 0 }
      library.send(delete ? .deleteAll : .cancel(file.lastPathComponent))
      try await waitFor { stub.state.stopped > 0 }
      #expect(library.options[0].progress == nil && library.options[0].error == nil)
      #expect(!FileManager.default.fileExists(atPath: file.path))
      #expect(preferences.selectedFiles == (delete ? [] : ["other-font.ttf"]))
    }
  }
  @Test func cancelledCompletionCannotCancelANewerDownloadOfTheSameFile() async throws {
    try await withLibrary { catalog, preferences, stub, file, _ in
      stub.update { $0.hold = true }
      let library = StudyFontLibrary(
        catalog: catalog, preferences: preferences, configuration: stub.configuration)
      library.send(.download(file.lastPathComponent))
      try await waitFor { stub.state.started == 1 }
      library.send(.cancel(file.lastPathComponent))
      stub.update { $0.hold = false }
      library.send(.download(file.lastPathComponent))
      try await waitFor { library.options[0].progress == nil }
      #expect(library.options[0].fontName != nil && library.options[0].error == nil)
      #expect(preferences.selectedFiles.contains(file.lastPathComponent))
    }
  }
  @Test func invalidFilesAndUnknownCatalogRequestsStayUnavailable() async throws {
    try await withLibrary { catalog, preferences, stub, file, _ in
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("not a font".utf8).write(to: file)
      #expect(StudyFont.fontNames(at: file).isEmpty)
      #expect(StudyFont.fontNames(at: URL(string: "https://example.test/font.ttf")!).isEmpty)
      let library = StudyFontLibrary(
        catalog: catalog, preferences: preferences, configuration: stub.configuration)
      library.send(.select(file.lastPathComponent, true))
      library.send(.download("unknown.ttf"))
      #expect(preferences.selectedFiles == ["other-font.ttf"] && stub.state.started == 0)
      #expect(library.options[0].progress == nil)
    }
  }
  @Test func nativeSelectionUsesAppleDefaultsWithoutReplacingOtherKeys() throws {
    let name = "font-preferences-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("keep", forKey: "unrelated")
    let store = DefaultsStudyFontPreferences(defaults: defaults)
    store.selectedFiles = ["b.ttf", "a.ttf"]
    #expect(defaults.stringArray(forKey: "native.selectedFonts") == ["a.ttf", "b.ttf"])
    #expect(DefaultsStudyFontPreferences(defaults: defaults).selectedFiles == ["a.ttf", "b.ttf"])
    #expect(defaults.string(forKey: "unrelated") == "keep")
  }
}

@MainActor private final class FontPreferencesFixture: StudyFontPreferences {
  var selectedFiles: Set<String>
  init(_ selected: Set<String>) { selectedFiles = selected }
}

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
    return value
  }
}
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
