import StudyCore
import StudyPersistence
import StudyUI
import SwiftUI

/// App-owned services. Feature views receive these same owners on every route.
@MainActor struct StudyAppAssembly {
  let model: StudyAppModel
  let fonts: StudyFontLibrary
  let audio: StudyAudioLibrary
  let defaults: UserDefaults
  let lessonSettings: StudyLessonSettings
  let subjectSettings: StudySubjectSettings
  let appearance: ColorScheme?
  let notice: String?

  init(
    model: StudyAppModel, fonts: StudyFontLibrary, audio: StudyAudioLibrary,
    defaults: UserDefaults = .standard, appearance: ColorScheme? = nil, notice: String? = nil
  ) {
    self.model = model
    self.fonts = fonts
    self.audio = audio
    self.defaults = defaults
    lessonSettings = StudyLessonSettings(store: DefaultsStudyLessonPreferences(defaults: defaults))
    subjectSettings = StudySubjectSettings(
      store: DefaultsStudySubjectPreferences(defaults: defaults))
    self.appearance = appearance
    self.notice = notice
  }
  static var isReviewFixture: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--review-fixture")
    #else
      false
    #endif
  }
  static func make() -> Self {
    #if DEBUG
      if isReviewFixture { return NativeStudyFixture.make() }
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    return Self(
      model: StudyAppModel(
        credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
        legacySnapshotURL: directory.appending(path: "snapshot-v1.json"),
        openStore: { try await StudyStore.open(at: directory.appending(path: "study.store")) }),
      fonts: StudyFontLibrary(
        catalog: .init(directory: directory.appending(path: "fonts"), bundledFonts: nil)),
      audio: StudyAudioLibrary(
        downloads: StudyAudioDownloads(directory: directory.appending(path: "audio"))))
  }
}
