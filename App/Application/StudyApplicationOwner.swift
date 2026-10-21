import Foundation
import Observation
import StudyCore
import StudyPersistence
import StudyUI
import SwiftUI

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import BackgroundTasks
  import OSLog
#endif

/// One bootstrap and service graph for scenes and background launches.
@MainActor @Observable final class StudyApplicationOwner {
  private(set) var services: StudyAppAssembly?
  private(set) var failure: String?
  @ObservationIgnored private var preparation: Task<Void, Never>?
  @ObservationIgnored private let factory: @MainActor () async throws -> StudyAppAssembly
  init(factory: @escaping @MainActor () async throws -> StudyAppAssembly = production) {
    self.factory = factory
  }
  func prepare() async {
    if let preparation {
      await preparation.value
      return
    }
    guard services == nil else { return }
    let task = Task {
      defer { preparation = nil }
      failure = nil
      do {
        let value = try await factory()
        await value.model.restore()
        guard value.model.restorationComplete else {
          throw StudySignInError.message(
            value.model.error ?? "Saved study data could not be restored.")
        }
        services = value
        value.mistakeSync?.start()
      } catch { failure = error.localizedDescription }
    }
    preparation = task
    await task.value
  }
  #if DEBUG
    private(set) var fixtureEventStatus: String?
    func receiveFixtureEvent(_ url: URL) -> Bool {
      guard let event = NativeStudyFixture.receive(url) else { return false }
      Task { fixtureEventStatus = await event.value }
      return true
    }
  #endif
  func refreshInBackground() async -> Bool {
    guard !Task.isCancelled else { return false }
    await prepare()
    guard !Task.isCancelled, let services else { return false }
    do {
      if let account = services.model.snapshot?.accountID,
        services.model.snapshot?.isSample == false
      {
        try await services.model.syncSavedWork(accountID: account)
      }
      try Task.checkCancellation()
      await services.notifications.refresh()
      return true
    } catch { return false }
  }
  #if os(iOS)
    nonisolated static var refreshIdentifier: String {
      (Bundle.main.bundleIdentifier ?? "com.davidsansome.wanikani") + ".study-refresh"
    }
    @concurrent nonisolated static func scheduleBackgroundRefresh() async {
      let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
      request.earliestBeginDate = Date().addingTimeInterval(1800)
      do { try await BGTaskScheduler.shared.submitTaskRequest(request) } catch {
        Logger(subsystem: "usagiunagi", category: "Background refresh")
          .debug("Study refresh was not scheduled: \(error.localizedDescription, privacy: .public)")
      }
    }
  #endif
  static func production() async throws -> StudyAppAssembly {
    #if DEBUG
      if StudyAppAssembly.isReviewFixture { return NativeStudyFixture.make() }
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    #if os(macOS)
      // The earlier native/TsurukameMacApp and unified Mac target used this ID and private root.
      // This running-app snapshot excludes known current competitors, not future/external writers.
      let identities = Set(
        [Bundle.main.bundleIdentifier, "com.pedrexus.tsurukame.mac"].compactMap { $0 })
      guard
        !NSWorkspace.shared.runningApplications.contains(where: {
          $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && identities.contains($0.bundleIdentifier ?? "")
        })
      else { throw StudyStoreOpeningError.alreadyOpen }
    #endif
    let store = try await StudyStore.openApplication(in: directory)
    var media = StudyMediaLayout.native
    #if os(iOS)
      let bootstrap = StudyLegacyBootstrap(
        store: store, sourceID: "ios-main",
        credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
        preferences: .init(defaults: .standard),
        readLegacy: {
          try LegacyStudyImporter.source(
            database: LegacyStudyImporter.databaseURL, defaults: .standard)
        })
      media = try await bootstrap.prepareApplication(legacyToken: {
        try LegacyPreferenceImporter.token(defaults: .standard)
      })
    #endif
    let endpoint =
      UserDefaults.standard.string(forKey: "native.apiBaseUrl")
      ?? WaniKaniClient.defaultBaseURL.absoluteString
    guard
      let normalized = DeveloperEndpoint.normalized(
        endpoint,
        defaultURL: WaniKaniClient.defaultBaseURL.absoluteString), let url = URL(string: normalized)
    else { throw StudyPreferenceImportError.invalidDestination("native.apiBaseUrl") }
    return .make(mediaLayout: media, baseURL: url, store: store)
  }
}

struct StudyApplicationWindow: View {
  let owner: StudyApplicationOwner
  @State private var links = StudyLinkInbox()
  @Environment(\.scenePhase) private var scenePhase
  private struct Activity: Equatable {
    let phase: ScenePhase
    let prepared: Bool
  }
  var body: some View {
    Group {
      if let services = owner.services {
        StudyRootView(
          model: services.model, automaticSync: services.automaticSync,
          appName: AppIdentity.name, appearance: services.appearance,
          notice: services.mistakeSync?.notice ?? services.notice,
          notifications: services.notifications,
          avatars: services.avatars, links: links
        )
        .environment(services.fonts).environment(services.audio)
        .environment(\.studyRadicalImages, services.radicalImages)
        .environment(\.studyVoiceCapture, services.voiceCapture)
        .environment(services.lessonSettings).environment(services.subjectSettings)
        .defaultAppStorage(services.defaults)
        .studyCloudPreferences(services.cloudPreferences)
      } else if let failure = owner.failure {
        VStack(spacing: 16) {
          ContentUnavailableView(
            "Could not open study data", systemImage: "externaldrive.badge.exclamationmark",
            description: Text(failure))
          Text("Your original account and saved work have been kept.").foregroundStyle(.secondary)
          Button("Try again") { Task { await owner.prepare() } }
        }.padding().accessibilityIdentifier("startup.failure")
      } else {
        ProgressView("Opening saved study data").accessibilityIdentifier("startup.loading")
      }
    }
    .task(id: Activity(phase: scenePhase, prepared: owner.services != nil)) {
      await owner.prepare()
      if !Task.isCancelled && scenePhase == .active {
        owner.services?.automaticSync.start()
        await owner.services?.mistakeSync?.wake()
      }
    }
    .onOpenURL { url in
      #if DEBUG
        if owner.receiveFixtureEvent(url) { return }
      #endif
      if let link = StudyLink(url: url) { links.receive(link) }
    }
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
      if let url = activity.webpageURL, let link = StudyLink(url: url) { links.receive(link) }
    }
    .onContinueUserActivity(StudyActivity.reviews.rawValue) { _ in links.receive(.reviews) }
    .onContinueUserActivity(StudyActivity.lessons.rawValue) { _ in links.receive(.lessons) }
    .overlay(alignment: .top) {
      #if DEBUG
        if let status = owner.fixtureEventStatus {
          Text(status).font(.caption).accessibilityIdentifier("fixture.eventStatus")
            .allowsHitTesting(false)
        }
      #endif
    }
  }
}
