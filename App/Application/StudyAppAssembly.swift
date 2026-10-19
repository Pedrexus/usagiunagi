import StudyCore
import StudyPersistence
import StudyUI
import SwiftUI

/// App-owned services. Feature views receive these same owners on every route.
@MainActor struct StudyAppAssembly {
  let model: StudyAppModel
  let automaticSync: StudyAutomaticSync
  let fonts: StudyFontLibrary
  let audio: StudyAudioLibrary
  let defaults: UserDefaults
  let notifications: StudyNotifications
  let lessonSettings: StudyLessonSettings
  let subjectSettings: StudySubjectSettings
  let appearance: ColorScheme?
  let notice: String?

  init(
    model: StudyAppModel, fonts: StudyFontLibrary, audio: StudyAudioLibrary,
    defaults: UserDefaults = .standard, notifications: StudyNotifications? = nil,
    appearance: ColorScheme? = nil, notice: String? = nil, paths: AsyncStream<Bool>? = nil
  ) {
    self.model = model
    automaticSync = StudyAutomaticSync(model: model, paths: paths)
    self.fonts = fonts
    self.audio = audio
    self.defaults = defaults
    self.notifications =
      notifications
      ?? StudyNotifications(preferences: DefaultsStudyNotificationPreferences(defaults: defaults))
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
  static func make(
    mediaLayout: StudyMediaLayout = .native, baseURL: URL = WaniKaniClient.defaultBaseURL
  ) -> Self {
    #if DEBUG
      if isReviewFixture { return NativeStudyFixture.make() }
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    let media = mediaLayout.directories(nativeRoot: directory)
    return Self(
      model: StudyAppModel(
        credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
        client: WaniKaniClient(baseURL: baseURL),
        legacySnapshotURL: directory.appending(path: "snapshot-v1.json"),
        openStore: { try await StudyStore.open(at: directory.appending(path: "study.store")) }),
      fonts: StudyFontLibrary(
        catalog: .init(
          directory: media.fonts,
          bundledFonts: mediaLayout == .legacyDocuments
            ? Bundle.main.resourceURL?.appending(path: "fonts") : nil)),
      audio: StudyAudioLibrary(
        downloads: StudyAudioDownloads(directory: media.audio)))
  }
}
