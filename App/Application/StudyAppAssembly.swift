import StudyCore
import StudyPersistence
import StudySpeech
import StudyUI
import SwiftUI

/// App-owned services. Feature views receive these same owners on every route.
@MainActor struct StudyAppAssembly {
  let model: StudyAppModel
  let automaticSync: StudyAutomaticSync
  let mistakeSync: StudyMistakeSync?
  let iCloudPreferences: StudyICloudPreferences?
  let fonts: StudyFontLibrary
  let audio: StudyAudioLibrary
  let defaults: UserDefaults
  let notifications: StudyNotifications
  let lessonSettings: StudyLessonSettings
  let subjectSettings: StudySubjectSettings
  let appearance: ColorScheme?
  let notice: String?
  let avatars: StudyAvatarCache
  let radicalImages: RadicalImageCache
  let voiceCapture: StudyVoiceCaptureFactory

  init(
    model: StudyAppModel, fonts: StudyFontLibrary, audio: StudyAudioLibrary,
    defaults: UserDefaults = .standard, notifications: StudyNotifications? = nil,
    companion: StudyCompanionDelivery? = nil, avatars: StudyAvatarCache? = nil,
    radicalImages: RadicalImageCache = .shared,
    mistakeICloud: (any StudyMistakeICloudStore)? = nil,
    iCloudPreferences: StudyICloudPreferences? = nil,
    voiceCapture: @escaping @Sendable () -> any VoiceCapture = { AppleVoiceCapture() },
    appearance: ColorScheme? = nil, notice: String? = nil,
    paths: AsyncStream<Bool>? = nil
  ) {
    self.model = model
    automaticSync = StudyAutomaticSync(model: model, paths: paths)
    mistakeSync = mistakeICloud.map { StudyMistakeSync(model: model, iCloud: $0) }
    self.iCloudPreferences = iCloudPreferences
    self.fonts = fonts
    self.audio = audio
    self.defaults = defaults
    self.notifications =
      notifications
      ?? StudyNotifications(preferences: DefaultsStudyNotificationPreferences(defaults: defaults))
    lessonSettings = StudyLessonSettings(
      store: DefaultsStudyLessonPreferences(
        defaults: defaults,
        changed: iCloudPreferences?.recordLessonChanges))
    subjectSettings = StudySubjectSettings(
      store: DefaultsStudySubjectPreferences(
        defaults: defaults,
        changed: iCloudPreferences?.recordSubjectChanges))
    self.radicalImages = radicalImages
    self.voiceCapture = StudyVoiceCaptureFactory(voiceCapture)
    self.appearance = appearance
    self.notice = notice
    self.avatars = avatars ?? StudyAvatarCache()
    reloadPreferences()
    if let companion { self.notifications.didRead = { companion.update($0) } }
    self.notifications.observe(model: model, lessonSettings: lessonSettings)
  }
  func reloadPreferences() {
    lessonSettings.reload()
    subjectSettings.reload()
    fonts.reloadSelection()
    audio.reloadPreferences()
  }
  static var isReviewFixture: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--review-fixture")
    #else
      false
    #endif
  }
  static func make(baseURL: URL, store: StudyStore) -> Self {
    #if os(iOS)
      let companion: StudyCompanionDelivery? = WatchHelper.sharedInstance.companion
    #else
      let companion: StudyCompanionDelivery? = nil
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    StudyWaniKaniSources.prepare(defaults: .standard)
    let iCloudPreferences = StudyICloudPreferences(
      directory: URL.applicationSupportDirectory.appending(path: "UsagiPrivatePreferences"),
      iCloudContainerIdentifier: Bundle.main.object(
        forInfoDictionaryKey: "UsagiPrivateICloudContainer") as? String,
      defaults: .standard)
    return Self(
      model: StudyAppModel(
        credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
        client: WaniKaniClient(baseURL: baseURL),
        preferenceCacheDirectory: URL.applicationSupportDirectory.appending(
          path: "UsagiWaniKaniSettings"),
        openStore: { store }),
      fonts: StudyFontLibrary(
        catalog: .init(directory: directory.appending(path: "fonts")),
        preferences: DefaultsStudyFontPreferences(
          changed: iCloudPreferences.recordFontChanges)),
      audio: StudyAudioLibrary(
        downloads: StudyAudioDownloads(directory: directory.appending(path: "audio")),
        preferences: DefaultsStudyAudioPreferences(
          changed: iCloudPreferences.recordAudioChanges)), companion: companion,
      mistakeICloud: AppleStudyMistakeICloudStore(store: .default),
      iCloudPreferences: iCloudPreferences)
  }
}
