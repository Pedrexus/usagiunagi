import Testing

@testable import StudyCore

struct WaniKaniPreferenceChangesTests {
  @Test(arguments: [false, true])
  func partialEditsPreserveUnrelatedServerValues(audio: Bool) {
    let server = WaniKaniPreferences(
      extraStudyAutoplayAudio: true, lessonsAutoplayAudio: true, lessonsBatchSize: 17,
      reviewsAutoplayAudio: true, reviewsDisplaySrsIndicator: true,
      reviewsPresentationOrder: "future_server_order")
    var pending = WaniKaniPreferenceChanges()
    pending.lessonsAutoplayAudio = !audio
    pending.lessonsBatchSize = 3
    var latest = WaniKaniPreferenceChanges()
    latest.lessonsAutoplayAudio = audio
    pending.merge(latest)
    pending.merge(WaniKaniPreferenceChanges())

    let edited = server.applying(pending)
    #expect(edited.lessonsAutoplayAudio == audio)
    #expect(edited.lessonsBatchSize == 3)
    #expect(edited.extraStudyAutoplayAudio && edited.reviewsAutoplayAudio)
    #expect(edited.reviewsDisplaySrsIndicator)
    #expect(edited.reviewsPresentationOrder == "future_server_order")
    #expect(pending.reviewsPresentationOrder == nil)
    #expect(server.applying(WaniKaniPreferenceChanges()) == server)
  }
}
