import Foundation
import StudyCore
import Testing

@MainActor struct AppleAudioPlaybackTests {
  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(predicate())
  }
  @Test func nativeObservationReportsFailureThenFinishesARealSilentWaveFile() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let playback = AppleStudyAudioPlayback()
    defer {
      playback.stop()
      try? FileManager.default.removeItem(at: root)
    }
    let broken = root.appending(path: "broken.mp3")
    try Data("invalid audio".utf8).write(to: broken)
    try playback.play(url: broken, interruptBackgroundAudio: false)
    try await wait { playback.error != nil }
    #expect(playback.state == .idle)
    var data = Data("RIFF".utf8)
    func append<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    append(UInt32(8036))
    data.append(Data("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(8000))
    append(UInt32(16000))
    append(UInt16(2))
    append(UInt16(16))
    data.append(Data("data".utf8))
    append(UInt32(8000))
    data.append(Data(repeating: 0, count: 8000))
    let file = root.appending(path: "silence.wav")
    try data.write(to: file)
    try playback.play(url: file, interruptBackgroundAudio: false)
    #expect(playback.error == nil)
    try await wait { playback.state == .playing }
    try await wait { playback.state == .idle }
    #expect(playback.error == nil)
    try playback.play(url: file, interruptBackgroundAudio: false)
    playback.stop()
    try await Task.sleep(for: .milliseconds(150))
    #expect(playback.state == .idle && playback.error == nil)
  }
}
