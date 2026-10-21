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
  let cloudPreferences: StudyCloudPreferences?
  let fonts: StudyFontLibrary
  let audio: StudyAudioLibrary
  let defaults: UserDefaults
  let notifications: StudyNotifications
  let lessonSettings: StudyLessonSettings
  let subjectSettings: StudySubjectSettings
  let appearance: ColorScheme?
  let notice: String?
  let avatars: LegacyAvatarCache
  let radicalImages: RadicalImageCache
  let voiceCapture: StudyVoiceCaptureFactory

  init(
    model: StudyAppModel, fonts: StudyFontLibrary, audio: StudyAudioLibrary,
    defaults: UserDefaults = .standard, notifications: StudyNotifications? = nil,
    companion: StudyCompanionDelivery? = nil, avatars: LegacyAvatarCache? = nil,
    radicalImages: RadicalImageCache = .shared,
    mistakeCloud: (any StudyMistakeCloudStore)? = nil,
    cloudPreferences: StudyCloudPreferences? = nil,
    voiceCapture: @escaping @Sendable () -> any VoiceCapture = { AppleVoiceCapture() },
    appearance: ColorScheme? = nil, notice: String? = nil,
    paths: AsyncStream<Bool>? = nil
  ) {
    self.model = model
    automaticSync = StudyAutomaticSync(model: model, paths: paths)
    mistakeSync = mistakeCloud.map { StudyMistakeSync(model: model, cloud: $0) }
    self.cloudPreferences = cloudPreferences
    self.fonts = fonts
    self.audio = audio
    self.defaults = defaults
    self.notifications =
      notifications
      ?? StudyNotifications(preferences: DefaultsStudyNotificationPreferences(defaults: defaults))
    lessonSettings = StudyLessonSettings(store: DefaultsStudyLessonPreferences(defaults: defaults))
    subjectSettings = StudySubjectSettings(
      store: DefaultsStudySubjectPreferences(defaults: defaults))
    self.radicalImages = radicalImages
    self.voiceCapture = StudyVoiceCaptureFactory(voiceCapture)
    self.appearance = appearance
    self.notice = notice
    self.avatars =
      avatars
      ?? LegacyAvatarCache(
        directory: URL.cachesDirectory.appending(path: "com.hpique.haneke/shared"))
    if let companion { self.notifications.didRead = { companion.update($0) } }
    self.notifications.observe(model: model, lessonSettings: lessonSettings)
  }
  static var isReviewFixture: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--review-fixture")
    #else
      false
    #endif
  }
  static func make(mediaLayout: StudyMediaLayout, baseURL: URL, store: StudyStore) -> Self {
    #if os(iOS)
      let companion: StudyCompanionDelivery? = WatchHelper.sharedInstance.companion
    #else
      let companion: StudyCompanionDelivery? = nil
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    let media = mediaLayout.directories(nativeRoot: directory)
    return Self(
      model: StudyAppModel(
        credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
        client: WaniKaniClient(baseURL: baseURL),
        legacySnapshotURL: directory.appending(path: "snapshot-v1.json"),
        openStore: { store }),
      fonts: StudyFontLibrary(
        catalog: .init(
          directory: media.fonts,
          bundledFonts: mediaLayout == .legacyDocuments
            ? Bundle.main.resourceURL?.appending(path: "fonts") : nil)),
      audio: StudyAudioLibrary(
        downloads: StudyAudioDownloads(directory: media.audio)), companion: companion,
      mistakeCloud: AppleStudyMistakeCloudStore(store: .default),
      cloudPreferences: StudyCloudPreferences(
        directory: URL.applicationSupportDirectory.appending(path: "UsagiPrivatePreferences"),
        cloudContainerIdentifier: Bundle.main.object(
          forInfoDictionaryKey: "UsagiPrivateCloudContainer") as? String,
        defaults: .standard))
  }
}
