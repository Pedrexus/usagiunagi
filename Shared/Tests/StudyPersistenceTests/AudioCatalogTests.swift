import Foundation
import StudyCore
import StudyPersistence
import Testing

struct AudioCatalogTests {
  @Test func nativeAudioCatalogRejectsOtherAccountsAndOmitsHiddenOrLockedSubjects() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Audio fixture")
    profile.level = 2
    profile.maxLevelGranted = 3
    var source = NativeStoreFixture(profile: profile)
    source.voices = [StudyVoiceActor(id: 7)]
    source.subjects = (1...4).map { id in
      var subject = CatalogSubject(id: Int64(id), kind: .vocabulary)
      subject.level = id
      subject.audio = [.init(url: "https://audio.example.test/\(id).mp3", voiceActorID: 7)]
      if id == 2 { subject.hiddenAt = 1 }
      return subject
    }
    try await store.seedFixture(source, accountID: "account", credentialID: "credential")
    let catalog = try await store.audioCatalog(accountID: "account")
    #expect(catalog.audio.map(\.subjectID) == [1, 3])
    #expect(catalog.voices.map(\.id) == [7] && catalog.currentLevel == 2)
    await #expect(throws: StudyStoreError.self) { try await store.audioCatalog(accountID: "other") }
  }
}
