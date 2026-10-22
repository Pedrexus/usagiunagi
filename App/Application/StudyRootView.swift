import Foundation
import StudyCore
import StudyPersistence
import SwiftUI

/// Shared navigation and screens. The host supplies identity and narrow platform appearance.
public struct StudyRootView: View {
  @Environment(\.studyICloudPreferences) private var iCloud
  @Bindable private var model: StudyAppModel
  private let appName: String
  private let automaticSync: StudyAutomaticSync
  private let appearance: ColorScheme?
  private let notice: String?
  private let notifications: StudyNotifications?
  private let avatars: StudyAvatarCache
  @Environment(\.scenePhase) private var scenePhase
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudySubjectSettings.self) private var subjectSettings
  @Environment(StudyAudioLibrary.self) private var audio
  @Environment(StudyFontLibrary.self) private var fonts
  @StoredReviewPreferences private var preferences
  private var waniKaniSources = StudyWaniKaniSources()
  @AppStorage("native.apiBaseUrl") private var apiEndpoint = WaniKaniClient.defaultBaseURL
    .absoluteString
  @AppStorage("native.avatarCacheRevision") private var avatarCacheRevision = 0
  @AppStorage("native.autoSwitchKeyboard") private var automaticJapanese = false
  @AppStorage("native.showMinutesForNextLevelUpReview") private var showMinutes = false
  @AppStorage("native.gravatarCustomEmail") private var avatarEmail = ""
  @AppStorage("native.avatarFallbacks") private var avatarFallbacks = Data()
  @Environment(\.displayScale) private var displayScale
  @State private var sceneID = UUID()
  @State private var shell = StudyShellState()
  @State private var tab = StudyTab.home
  @State private var path: [StudyDestination] = []
  @State private var settingsPath: [StudyDestination] = []
  @State private var showSettings = false
  @State private var subject: StudySubject?
  @State private var signIn: StudySignIn
  @Bindable private var links: StudyLinkInbox
  @State private var linkMessage: String?
  @State private var openIncomingLink = false
  @State private var wrapUpRequested = false
  @State private var confirmDisconnect = false
  @Environment(\.openURL) private var openURL
  @Environment(\.appearsActive) private var appearsActive
  init(
    model: StudyAppModel, automaticSync: StudyAutomaticSync, appName: String,
    appearance: ColorScheme? = nil, notice: String? = nil,
    notifications: StudyNotifications? = nil,
    avatars: StudyAvatarCache,
    links: StudyLinkInbox = .init()
  ) {
    self.model = model
    self.automaticSync = automaticSync
    _signIn = State(
      initialValue: StudySignIn {
        try await model.connect($0)
        await automaticSync.wake()
      })
    self.appName = appName
    self.appearance = appearance
    self.notice = notice
    self.notifications = notifications
    self.avatars = avatars
    self.links = links
  }
  private var diagnosticArchive: StudyDiagnosticArchive? {
    guard let snapshot = model.snapshot, !snapshot.isSample, let accountID = snapshot.accountID,
      let store = model.savedWorkStore
    else { return nil }
    return StudyDiagnosticArchive(store: store, accountID: accountID)
  }
  private struct AudioReadKey: Equatable {
    let accountID: String?
    let savedAt: Date?
    let profile: StudyAccountProfile?
  }
  private struct PreferenceReadKey: Equatable {
    let accountID: String?
    let savedAt: Date?
    let source: UUID
    let phase: ScenePhase
  }
  private var notices: some View {
    VStack(spacing: 4) {
      if let notice { Text(notice).font(.caption).padding(6) }
      if let link = links.pending.first {
        HStack {
          Text(link.title)
          Button("Open") { openIncomingLink = true }.accessibilityIdentifier("applink.open")
            .disabled(model.isSyncing || model.snapshot?.isSample != false)
          Button("Dismiss") {
            if links.pending.first == link { links.pending.removeFirst() }
            openIncomingLink = false
          }.accessibilityIdentifier("applink.dismiss")
        }.font(.callout).padding(8)
      }
      if let message = linkMessage {
        Label(message, systemImage: "link").font(.callout).padding(8)
          .accessibilityIdentifier("applink.message")
      }
      if let message = automaticSync.notice {
        Label(message, systemImage: "arrow.triangle.2.circlepath").font(.callout).padding(8)
          .accessibilityIdentifier("app.automaticSync")
      }
      if let error = model.error, signIn.error == nil {
        Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding(8)
      }
    }
  }
  public var body: some View {
    VStack(spacing: 0) {
      notices
      NavigationStack(path: $path) {
        StudyShellView(
          state: shell,
          signIn: {
            if model.reauthenticationContext != nil { presentAccount() }
          },
          manageToken: {
            if model.reauthenticationContext != nil { presentAccount() }
            openURL(URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
          },
          acknowledgeAccountIssue: {
            if let context = model.reauthenticationContext {
              model.acknowledgeAccountIssue(context)
            }
          }
        ) {
          StudyTabs(selection: $tab) {
            Group {
              if model.snapshot == nil {
                account
              } else {
                NativeHomeDashboardView(
                  model: model, state: shell, active: tab == .home && path.isEmpty && !showSettings
                ) {
                  path = [$0]
                }
              }
            }
          } practice: {
            KatakanaPracticeMenu { path = [.katakana] }
          } statistics: {
            if let snapshot = model.snapshot {
              TimelineView(.everyMinute) { context in
                StudyDashboard(snapshot: snapshot, now: context.date) { id in
                  subject = snapshot.subjects.first { $0.id == id }
                }
              }
            } else {
              account
            }
          }
        }.navigationTitle(tab == .home ? "Home" : tab == .practice ? "Practice" : "Stats")
          .toolbarTitleDisplayMode(.inline)
          .navigationDestination(for: StudyDestination.self) { value in destination(value) }
          .toolbar {
            if path.isEmpty {
              ToolbarItemGroup(placement: .primaryAction) {
                Button("Search", systemImage: "magnifyingglass") { path = [.search] }
                  .accessibilityIdentifier("app.search")
                Button("Settings", systemImage: "gearshape") {
                  settingsPath = []
                  showSettings = true
                }.accessibilityIdentifier("app.settings")
              }
              ToolbarItemGroup(placement: .automatic) {
                if tab == .home { savedWorkButton }
                if tab != .practice { refreshButton }
              }
            }
          }
      }
    }.preferredColorScheme(appearance ?? $preferences.colorScheme)
      .handlesExternalEvents(preferring: appearsActive ? ["*"] : [], allowing: ["*"])
      .task(
        id: LinkReadKey(
          account: model.snapshot?.accountID, busy: model.isSyncing,
          link: links.pending.first,
          canOpen: canOpenIncomingLink)
      ) {
        await openLinkIfReady()
      }
      .onAppear {
        updateHeader()
        updateSyncActivity()
        updateAccountIssue()
      }
      .onDisappear {
        automaticSync.removeScene(sceneID)
        iCloud?.updateScene(sceneID, studying: false)
      }
      .onChange(of: scenePhase) { _, phase in
        updateSyncActivity()
        updateAccountIssue()
        if phase == .active { Task { await automaticSync.wake() } }
      }
      .onChange(of: path) { _, values in
        updateSyncActivity()
        updateAccountIssue()
        if !values.contains(where: {
          switch $0 {
          case .reviews, .practice: true
          default: false
          }
        }) {
          wrapUpRequested = false
        }
      }
      .onChange(of: model.dataRevision) { _, _ in updateHeader() }
      .onChange(of: model.accountIssue) { _, _ in updateAccountIssue() }
      .onChange(of: appearsActive) { _, _ in updateAccountIssue() }
      .onChange(of: subject?.id) { _, _ in updateAccountIssue() }
      .onChange(of: showSettings) { _, visible in
        if !visible { updateHeader() }
        updateAccountIssue()
      }
      .onChange(of: avatarCacheRevision) { _, _ in
        shell.avatarRevision += 1
      }
      .onChange(of: avatarEmail) { _, _ in if !showSettings { updateHeader() } }
      .onChange(of: avatarFallbacks) { _, _ in if !showSettings { updateHeader() } }
      .onChange(of: displayScale) { _, _ in if !showSettings { updateHeader() } }
      .onChange(of: model.isSyncing, initial: true) { _, active in
        shell.progress = active ? Progress(totalUnitCount: -1) : nil
      }
      .onChange(of: model.snapshot?.accountID) { previous, current in
        if previous != nil, previous != current { links.pending.removeAll() }
        openIncomingLink = false
        linkMessage = nil
        wrapUpRequested = false
        audio.updateCatalog(nil)
        path = []
        settingsPath = []
        showSettings = false
        subject = nil
        signIn.cancel()
        tab = .home
        updateHeader()
      }
      .task(
        id: AudioReadKey(
          accountID: model.snapshot?.accountID, savedAt: model.snapshot?.savedAt,
          profile: model.profile)
      ) {
        guard let snapshot = model.snapshot, !snapshot.isSample, let account = snapshot.accountID,
          let store = model.savedWorkStore
        else {
          audio.updateCatalog(nil)
          return
        }
        do {
          let catalog = try await store.audioCatalog(accountID: account)
          try Task.checkCancellation()
          audio.updateCatalog(catalog)
        } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
      }
      .task(
        id: PreferenceReadKey(
          accountID: model.snapshot?.accountID, savedAt: model.snapshot?.savedAt,
          source: model.preferenceSourceRevision, phase: scenePhase)
      ) {
        if scenePhase == .active { await model.refreshWaniKaniPreferences() }
      }
      .sheet(isPresented: $showSettings) {
        NavigationStack(path: $settingsPath) {
          StudySettingsView(
            account: model.snapshot == nil ? nil : shell, model: model,
            destination: settingsDestination
          ) {
            NavigationLink("Developer options", value: StudyDestination.developerSettings)
              .accessibilityIdentifier("settings.developer")
          } accountActions: {
            Button("Saved work") { settingsPath.append(.savedWork) }
            Button("WaniKani account", action: presentAccount)
          }
          .navigationDestination(for: StudyDestination.self) { value in
            destination(value).toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showSettings = false }
              }
            }
          }
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showSettings = false }
            }
          }
        }.presentationSizing(.form)
      }
      .sheet(item: $subject) { value in
        NavigationStack {
          Group {
            if let accountID = model.snapshot?.accountID, let store = model.savedWorkStore,
              model.snapshot?.isSample == false
            {
              NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: value.id)
                .navigationTitle("Subject")
            } else {
              PreviewSubjectDetail(subject: value, maximumLevel: model.maximumContentLevel)
            }
          }.toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { subject = nil } }
          }
        }
        .presentationSizing(.form)
      }
      .tint(StudyPalette.radical)
      .environment(\.studyAvatars, avatars)
      .environment(\.waniKaniPreferences, model.effectiveWaniKaniPreferences)
  }
  private func updateSyncActivity() {
    let studying = path.contains {
      switch $0 {
      case .reviews, .lessons, .practice, .katakana: true
      default: false
      }
    }
    automaticSync.updateScene(sceneID, active: scenePhase == .active, studying: studying)
    iCloud?.updateScene(sceneID, studying: studying)
  }
  private var reviewBinding: Binding<ReviewPreferences> {
    Binding(
      get: { preferences },
      set: { value in
        do { try $preferences.applyChanges(from: preferences, to: value) } catch {
          model.error = error.localizedDescription
        }
      })
  }
  private func settingsDestination(_ page: StudySettingsPage) -> StudyDestination {
    switch page {
    case .appearance: .appearanceSettings
    case .lessons: .lessonSettings
    case .reviews: .reviewSettings
    case .subjects: .subjectSettings
    }
  }
  @ViewBuilder private func destination(_ value: StudyDestination) -> some View {
    switch value {
    case .account: account
    case .katakana: KatakanaPracticeSessionView()
    case .developerSettings:
      DeveloperSettingsView(
        endpoint: $apiEndpoint,
        defaultEndpoint: WaniKaniClient.defaultBaseURL.absoluteString,
        studyArchive: diagnosticArchive,
        applyEndpoint: { value in
          guard let url = URL(string: value) else { throw WaniKaniClient.APIError.invalidResponse }
          try model.setAPIEndpoint(url)
        },
        clearAvatarCache: {
          await avatars.clear()
          avatarCacheRevision += 1
        })
    case .lessonSettings: LessonSettingsView(settings: lessonSettings)
    case .appearanceSettings:
      AppearanceSettingsView(
        appearance: reviewBinding.appearance,
        email: $avatarEmail.syncing(.avatarEmail, with: iCloud),
        notifications: notifications)
    case .subjectSettings:
      SubjectSettingsView(
        settings: subjectSettings,
        skipKanjiReadings: reviewBinding.sessionOptions.skipKanjiReadings)
    case .fonts: FontLibraryView(library: fonts)
    case .offlineAudio: AudioLibraryView(library: audio)
    case .reviewSettings:
      Form {
        FullReviewSettingsContent(
          preferences: reviewBinding,
          fonts: { settingsPath.append(.fonts) },
          offlineAudio: { settingsPath.append(.offlineAudio) }
        ) {
          Toggle(
            "Show minutes for next level-up review",
            isOn: $showMinutes.syncing(.showMinutes, with: iCloud)
          )
          .accessibilityIdentifier("settings.showMinutesForNextLevelUpReview")
        } answers: {
          #if os(iOS)
            StudyInputSettings(automaticJapanese: $automaticJapanese)
          #endif
        }
      }.formStyle(.grouped).navigationTitle("Reviews")
    case .forecast: NativeForecastView(model: model)
    case .reviews, .lessons, .practice, .savedWork, .catalog, .search, .subject:
      if let snapshot = model.snapshot, !snapshot.isSample, let accountID = snapshot.accountID,
        let store = model.savedWorkStore
      {
        switch value {
        case .reviews:
          NativeReviewView(
            store: store, accountID: accountID, wrapUpRequested: $wrapUpRequested,
            finished: finished
          )
          .userActivity(StudyActivity.reviews.rawValue) { StudyActivity.reviews.configure($0) }
        case .lessons(let automatic):
          NativeLessonView(
            store: store, accountID: accountID,
            automaticBatchSize: automatic
              ? lessonSettings.value.effectiveBatchSize(
                waniKani: model.effectiveWaniKaniPreferences,
                followWaniKani: waniKaniSources.lessonBatch)
              : nil,
            finished: finished
          )
          .userActivity(StudyActivity.lessons.rawValue) { StudyActivity.lessons.configure($0) }
        case .practice(let scope):
          NativeReviewView(
            store: store, accountID: accountID, mode: .practice(scope),
            wrapUpRequested: $wrapUpRequested, finished: finished)
        case .subject(let id):
          NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id)
            .navigationTitle("Subject")
        case .savedWork:
          SavedWorkView(
            store: store, accountID: accountID, isSyncing: model.isSyncing,
            compareSavedWork: model.compareSavedWork
          ) {
            try await model.syncSavedWork(accountID: accountID)
            await automaticSync.wake()
          }
          .navigationTitle("Saved work")
        case .catalog(let query, let remaining):
          let mode: SubjectCatalogView.Mode =
            if remaining { .remaining } else if query.level > 0 { .level } else {
              switch query.scope {
              case .apprentice, .guru, .master, .enlightened, .burned: .stage
              case .excluded: .excluded
              default: .all
              }
            }
          NativeSubjectCatalogView(
            store: store, accountID: accountID, maximumLevel: model.maximumContentLevel,
            initialQuery: query, mode: mode,
            title: remaining
              ? "Remaining" : query.level > 0 ? "Level \(query.level)" : query.scope.rawValue)
        case .search:
          NativeSubjectCatalogView(
            store: store, accountID: accountID, maximumLevel: model.maximumContentLevel,
            mode: .search, title: "Search")
        default: EmptyView()
        }
      } else if case .catalog(let query, let remaining) = value, let snapshot = model.snapshot {
        previewCatalog(snapshot, query: query, remaining: remaining)
      } else if value == .search, let snapshot = model.snapshot {
        previewCatalog(snapshot, query: .init(), mode: .search)
      } else {
        ContentUnavailableView(
          "Connect to study", systemImage: "person.crop.circle",
          description: Text(
            "Connect and refresh your WaniKani account to study with its saved catalog. Previews do not change your account."
          ))
        Button("Connect account") {
          presentAccount()
        }
      }
    }
  }
  private var refreshButton: some View {
    Button("Refresh", systemImage: "arrow.clockwise") {
      Task {
        await model.refresh()
        await automaticSync.wake()
      }
    }
    .disabled(model.isSyncing || model.snapshot?.isSample != false)
  }
  private var savedWorkButton: some View {
    Button("Saved work", systemImage: "tray.and.arrow.up") { path = [.savedWork] }
      .accessibilityIdentifier("home.savedWork")
  }
  private func finished() {
    path = []
    Task { await model.reloadSavedSnapshot() }
  }
  private func presentAccount() {
    let context = model.reauthenticationContext
    signIn.cancel()
    signIn = StudySignIn(forcedEmail: context?.username) { token in
      if let context {
        try await model.reauthenticate(token, context: context)
      } else {
        try await model.connect(token)
      }
      await automaticSync.wake()
    }
    settingsPath = [.account]
    showSettings = true
  }
  private func updateAccountIssue() {
    guard let issue = model.accountIssue else {
      shell.accountRestored()
      return
    }
    guard !issue.acknowledged else {
      shell.accountIssue = nil
      return
    }
    guard scenePhase == .active, appearsActive, path.isEmpty, !showSettings, subject == nil else {
      return
    }
    shell.reportAccountIssue(issue.reason == .unauthorized ? .unauthorized : .hibernating)
  }
  private func updateHeader() {
    shell.username = model.snapshot?.username ?? appName
    shell.level = model.snapshot?.currentLevel ?? 0
    if !showSettings {
      shell.avatar =
        model.snapshot?.isSample == false
        ? StudyAvatar.url(
          email: StudyAvatar.email(
            custom: avatarEmail, fallbacks: avatarFallbacks, accountID: model.snapshot?.accountID),
          pixelSize: Double(80 * displayScale)) : nil
    }
    guard let snapshot = model.snapshot, !snapshot.requiresAssignmentRefresh else {
      shell.learnedKanji = nil
      return
    }
    let kanji = Set(snapshot.subjects.filter { $0.kind == .kanji }.map(\.id))
    shell.learnedKanji =
      Set(
        snapshot.assignments.filter { $0.srsStageNumber >= 5 && kanji.contains($0.subjectID) }.map(
          \.subjectID)
      ).count
  }
  private func previewCatalog(
    _ snapshot: StudySnapshot, query: SubjectCatalogQuery,
    remaining: Bool = false, mode: SubjectCatalogView.Mode = .all
  ) -> some View {
    PreviewCatalogView(
      snapshot: snapshot, maximumLevel: model.maximumContentLevel,
      query: query, remaining: remaining, mode: mode
    ) { subject = $0 }
  }

  private struct LinkReadKey: Equatable {
    let account: String?
    let busy: Bool
    let link: StudyLink?
    let canOpen: Bool
  }
  private var canOpenIncomingLink: Bool {
    openIncomingLink || (path.isEmpty && tab != .practice && !showSettings && subject == nil)
  }
  private func navigate(to destination: StudyDestination) {
    let existing = path.lastIndex { value in
      if case .lessons = destination, case .lessons = value { return true }
      return value == destination
    }
    if let existing {
      path = Array(path.prefix(through: existing))
    } else {
      path.append(destination)
    }
  }
  private func openLinkIfReady() async {
    guard let link = links.pending.first, !model.isSyncing,
      let accountID = model.snapshot?.accountID, model.snapshot?.isSample == false,
      let store = model.savedWorkStore,
      canOpenIncomingLink
    else { return }
    do {
      let target: StudyDestination?
      var message: String?
      switch link {
      case .reviews, .lessons:
        if let saved = try await store.session(accountID: accountID) {
          target = StudyDestination(resuming: saved.session)
          let requested: StudyDestination = link == .reviews ? .reviews : .lessons(automatic: true)
          if target != requested {
            message =
              "Resumed your saved study session. Finish or end it before starting different work."
          }
        } else {
          target = link == .reviews ? .reviews : .lessons(automatic: true)
        }
      case .subject(let reference):
        target = .subject(try await store.linkedSubjectID(reference, accountID: accountID))
      case .activate, .wrapUp: target = nil
      }
      try Task.checkCancellation()
      guard model.snapshot?.accountID == accountID, links.pending.first == link else { return }
      links.pending.removeFirst()
      openIncomingLink = false
      showSettings = false
      subject = nil
      linkMessage = message
      if let target { navigate(to: target) }
      if link == .wrapUp {
        let index = path.lastIndex { value in
          switch value {
          case .reviews, .practice: true
          default: false
          }
        }
        if let index {
          path = Array(path.prefix(through: index))
          wrapUpRequested = true
        } else {
          linkMessage = "Open a review session before wrapping it up."
        }
      }
    } catch {
      guard !Task.isCancelled, model.snapshot?.accountID == accountID,
        links.pending.first == link
      else { return }
      links.pending.removeFirst()
      openIncomingLink = false
      linkMessage = error.localizedDescription
    }
  }
  private var account: some View {
    Form {
      StudySignInFields(model: signIn, submitTitle: "Connect and sync") { _ in
        showSettings = false
        tab = .home
        Task { await notifications?.requestAuthorizationIfNeeded() }
      }.disabled(model.isSyncing)
      Section("On this device") {
        Text("Your API token stays in this device's Keychain; saved work stays on this device.")
          .font(.caption).foregroundStyle(.secondary)
        if let snapshot = model.snapshot, !snapshot.isSample {
          LabeledContent("Connected", value: snapshot.username)
          if model.contentAccessVerified {
            LabeledContent("Content access", value: "Through level \(model.maximumContentLevel)")
          }
          Button("Disconnect and remove local snapshot", role: .destructive) {
            confirmDisconnect = true
          }.disabled(model.isDisconnecting)
        }
      }
      Section("Explore") {
        Button("Preview free levels 1–3") {
          model.loadPreview()
          showSettings = false
          tab = .home
          path = [.catalog(.init())]
        }.disabled(model.isSyncing)
        Text(
          "The level preview contains display readings and meanings for browsing. It is never uploaded or saved over your account cache."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).navigationTitle("Account").onDisappear { signIn.cancel() }
      .confirmationDialog(
        "Disconnect account?", isPresented: $confirmDisconnect, titleVisibility: .visible
      ) {
        Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "The API token and cached statistics are removed from this device. Saved answers and notes remain tied to this account and can sync after reconnecting."
        )
      }
  }
}

private struct PreviewSubjectDetail: View {
  let subject: StudySubject
  let maximumLevel: Int
  var body: some View {
    Form {
      if subject.level > maximumLevel {
        ContentUnavailableView(
          "Subscription level limit", systemImage: "lock",
          description: Text("Refresh your account to verify access to this level."))
      } else {
        Text(subject.characters.isEmpty ? subject.meaning : subject.characters).font(.largeTitle)
          .foregroundStyle(StudyPalette.color(for: subject.kind))
        LabeledContent("Meaning", value: subject.meaning)
        LabeledContent(
          "Readings",
          value: subject.readings.isEmpty ? "None" : subject.readings.joined(separator: " · "))
        LabeledContent("WaniKani level", value: String(subject.level))
        if let url = subject.documentURL, url.scheme == "https", url.host == "www.wanikani.com" {
          Link("Open full mnemonics on WaniKani", destination: url)
        }
      }
    }.formStyle(.grouped).navigationTitle("Subject")
  }
}

/// Keep a stable collection identity while searches and answer visibility change.
private struct PreviewCatalogView: View {
  let snapshot: StudySnapshot
  let maximumLevel: Int
  let query: SubjectCatalogQuery
  let remaining: Bool
  let mode: SubjectCatalogView.Mode
  let openSubject: (StudySubject) -> Void
  @State private var collection = SubjectCatalogCollection(items: [])
  @State private var level = 0
  @State private var showAnswers = true
  var body: some View {
    SubjectCatalogView(
      collection: collection, title: "Subjects",
      mode: remaining ? .remaining : query.level > 0 ? .level : mode,
      showAnswers: $showAnswers, maximumLevel: maximumLevel,
      selectedLevel: query.level > 0 ? $level : nil, initialQuery: query
    ) { id in
      if let subject = snapshot.subjects.first(where: { $0.id == id }) { openSubject(subject) }
    }.task(id: snapshot.savedAt) {
      let available = NativeHomeDashboardView.preview(snapshot)
      let assignments = Dictionary(
        available.assignments.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
      collection = .init(
        items: available.subjects.filter { $0.level <= maximumLevel }.map { value in
          let status: SubjectCatalogItem.Status =
            assignments[value.id].flatMap { StudySRSStage(rawValue: $0.srsStage) }
            .map { .studying($0, reviewAt: nil, guruAt: nil) } ?? .unassigned
          return SubjectCatalogItem(subject: value, status: status)
        }.filter { !remaining || ($0.status.stage?.rawValue ?? 0) < 5 })
      level = query.level
    }
  }
}
