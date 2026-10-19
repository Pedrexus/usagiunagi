import Foundation
import StudyCore
import StudyPersistence
import SwiftUI

/// Shared navigation and screens. The host supplies identity and narrow platform appearance.
public struct StudyRootView: View {
  @Bindable private var model: StudyAppModel
  private let appName: String
  private let appearance: ColorScheme?
  private let notice: String?
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudySubjectSettings.self) private var subjectSettings
  @Environment(StudyAudioLibrary.self) private var audio
  @Environment(StudyFontLibrary.self) private var fonts
  @StoredReviewPreferences private var preferences
  @State private var shell = StudyShellState()
  @State private var tab = StudyTab.home
  @State private var path: [StudyDestination] = []
  @State private var settingsPath: [StudyDestination] = []
  @State private var showSettings = false
  @State private var subject: StudySubject?
  @State private var token = ""
  @State private var incomingLinks: [StudyLink] = []
  @State private var linkMessage: String?
  @State private var openIncomingLink = false
  @State private var wrapUpRequested = false
  @Environment(\.openURL) private var openURL
  @Environment(\.appearsActive) private var appearsActive
  public init(
    model: StudyAppModel, appName: String, appearance: ColorScheme? = nil, notice: String? = nil
  ) {
    self.model = model
    self.appName = appName
    self.appearance = appearance
    self.notice = notice
  }
  private struct AudioReadKey: Equatable {
    let accountID: String?
    let savedAt: Date?
  }
  public var body: some View {
    NavigationStack(path: $path) {
      StudyShellView(
        state: shell, search: { path = [.search] },
        settings: {
          settingsPath = []
          showSettings = true
        },
        signIn: {
          settingsPath = [.account]
          showSettings = true
        },
        manageToken: {
          openURL(URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
        }
      ) {
        StudyTabs(selection: $tab) {
          Group {
            if model.snapshot == nil {
              account
            } else {
              NativeHomeDashboardView(model: model, active: tab == .home && path.isEmpty) {
                path = [$0]
              }
            }
          }
        } practice: {
          KatakanaPracticeView()
        } statistics: {
          if let snapshot = model.snapshot {
            StudyDashboard(snapshot: snapshot) { id in
              subject = snapshot.subjects.first { $0.id == id }
            }
          } else {
            account
          }
        }
      }.navigationTitle(tab == .home ? "Home" : tab == .practice ? "Practice" : "Stats")
        .navigationDestination(for: StudyDestination.self) { value in destination(value) }
        .toolbar {
          if tab == .home { savedWorkButton }
          if tab != .practice { refreshButton }
        }
    }.preferredColorScheme(appearance ?? $preferences.colorScheme)
      .handlesExternalEvents(preferring: appearsActive ? ["*"] : [], allowing: ["*"])
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 4) {
          if let notice {
            Text(notice).font(.caption).padding(6)
          }
          if let link = incomingLinks.first {
            HStack {
              Text(link.title)
              Button("Open") { openIncomingLink = true }.accessibilityIdentifier("applink.open")
                .disabled(model.isSyncing || model.snapshot?.isSample != false)
              Button("Dismiss") {
                if incomingLinks.first == link { incomingLinks.removeFirst() }
                openIncomingLink = false
              }
              .accessibilityIdentifier("applink.dismiss")
            }.font(.callout).padding(8)
          }
          if let message = linkMessage {
            Label(message, systemImage: "link").font(.callout).padding(8).accessibilityIdentifier(
              "applink.message")
          }
          if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding(8)
          }
        }
      }
      .onOpenURL { url in if let link = StudyLink(url: url) { receive(link) } }
      .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
        if let url = activity.webpageURL, let link = StudyLink(url: url) { receive(link) }
      }
      .onContinueUserActivity(StudyActivity.reviews.rawValue) { _ in receive(.reviews) }
      .onContinueUserActivity(StudyActivity.lessons.rawValue) { _ in receive(.lessons) }
      .task(
        id: LinkReadKey(
          account: model.snapshot?.accountID, busy: model.isSyncing,
          link: incomingLinks.first,
          canOpen: canOpenIncomingLink)
      ) {
        await openLinkIfReady()
      }
      .onAppear { updateHeader() }
      .onChange(of: path) { _, values in
        if !values.contains(where: {
          switch $0 {
          case .reviews, .practice: true
          default: false
          }
        }) {
          wrapUpRequested = false
        }
      }
      .onChange(of: model.snapshot?.savedAt) { _, _ in updateHeader() }
      .onChange(of: model.snapshot?.pendingReviews) { _, _ in updateHeader() }
      .onChange(of: model.isSyncing) { _, active in
        shell.progress = active ? Progress(totalUnitCount: -1) : nil
      }
      .onChange(of: model.snapshot?.accountID) { previous, current in
        if previous != nil, previous != current { incomingLinks.removeAll() }
        openIncomingLink = false
        linkMessage = nil
        wrapUpRequested = false
        audio.updateCatalog(nil)
        path = []
        settingsPath = []
        showSettings = false
        subject = nil
        token = ""
        updateHeader()
      }
      .task(
        id: AudioReadKey(accountID: model.snapshot?.accountID, savedAt: model.snapshot?.savedAt)
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
      .sheet(isPresented: $showSettings) {
        NavigationStack(path: $settingsPath) {
          Form {
            Button("Lessons") { settingsPath.append(.lessonSettings) }.accessibilityIdentifier(
              "settings.page.lessons")
            Button("Subject details") { settingsPath.append(.subjectSettings) }
              .accessibilityIdentifier("settings.page.subjects")
            Button("Review settings") { settingsPath.append(.reviewSettings) }
            Button("Saved work") { settingsPath.append(.savedWork) }
            Button("WaniKani account") { settingsPath = [.account] }
          }.formStyle(.grouped).navigationTitle("Settings")
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
  }
  @ViewBuilder private func destination(_ value: StudyDestination) -> some View {
    switch value {
    case .account: account
    case .lessonSettings: LessonSettingsView(settings: lessonSettings)
    case .subjectSettings:
      SubjectSettingsView(
        settings: subjectSettings,
        skipKanjiReadings: Binding(
          get: { preferences.sessionOptions.skipKanjiReadings },
          set: { value in
            let old = preferences
            var new = old
            new.sessionOptions.skipKanjiReadings = value
            do { try $preferences.applyChanges(from: old, to: new) } catch {
              model.error = error.localizedDescription
            }
          }))
    case .fonts: FontLibraryView(library: fonts)
    case .offlineAudio: AudioLibraryView(library: audio)
    case .reviewSettings:
      ReviewSettingsPanel(
        preferences: preferences,
        changed: { old, new in
          do { try $preferences.applyChanges(from: old, to: new) } catch {
            model.error = error.localizedDescription
          }
        }, fonts: { settingsPath.append(.fonts) },
        offlineAudio: { settingsPath.append(.offlineAudio) },
        supportsSessionOptions: true)
    case .forecast: NativeForecastView(model: model)
    case .reviews, .lessons, .practice, .savedWork, .catalog, .search, .subject:
      if let snapshot = model.snapshot, !snapshot.isSample, let accountID = snapshot.accountID,
        let store = model.savedWorkStore
      {
        switch value {
        case .reviews:
          NativeReviewView(
            store: store, accountID: accountID, wrapUpRequested: $wrapUpRequested,
            finished: finished)
        case .lessons(let automatic):
          NativeLessonView(
            store: store, accountID: accountID,
            automaticBatchSize: automatic ? lessonSettings.value.batchSize : nil,
            finished: finished)
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
          ) { try await model.syncSavedWork(accountID: accountID) }
          .navigationTitle("Saved work")
        case .catalog(let query, let remaining):
          NativeSubjectCatalogView(
            store: store, accountID: accountID, maximumLevel: model.maximumContentLevel,
            initialQuery: query, mode: remaining ? .remaining : query.level > 0 ? .level : .all,
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
          settingsPath = [.account]
          showSettings = true
        }
      }
    }
  }
  private var refreshButton: some View {
    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
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
  private func updateHeader() {
    shell.username = model.snapshot?.username ?? appName
    shell.level = model.snapshot?.currentLevel ?? 0
    shell.onVacation = model.snapshot?.onVacation ?? false
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
  private func receive(_ link: StudyLink) {
    guard link != .activate, incomingLinks.last != link else { return }
    linkMessage = nil
    incomingLinks.append(link)
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
    guard let link = incomingLinks.first, !model.isSyncing,
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
      guard model.snapshot?.accountID == accountID, incomingLinks.first == link else { return }
      incomingLinks.removeFirst()
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
        incomingLinks.first == link
      else { return }
      incomingLinks.removeFirst()
      openIncomingLink = false
      linkMessage = error.localizedDescription
    }
  }
  private var account: some View {
    Form {
      Section("WaniKani account") {
        StudyTokenEntry(token: $token)
        Text(
          "Connect and refresh use reading access. Sending saved work also requires review, assignment or study-material write permissions. The token stays in this device's Keychain; saved work stays on this device."
        )
        .font(.caption).foregroundStyle(.secondary)
        Button("Connect and sync") {
          Task {
            if await model.connect(token) {
              token = ""
              showSettings = false
              tab = .home
            }
          }
        }
        .disabled(model.isSyncing || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let snapshot = model.snapshot, !snapshot.isSample {
          LabeledContent("Connected", value: snapshot.username)
          if model.contentAccessVerified {
            LabeledContent("Content access", value: "Through level \(model.maximumContentLevel)")
          }
          Button("Disconnect and remove local snapshot", role: .destructive) {
            Task { await model.disconnect() }
          }.disabled(model.isDisconnecting)
        }
      }
      Section("Explore") {
        Button("Preview free levels 1–3") {
          model.loadSample(freeLevels: true)
          showSettings = false
          tab = .home
          path = [.catalog(.init())]
        }.disabled(model.isSyncing)
        Button("Use sample data") {
          model.loadSample()
          showSettings = false
          tab = .home
          path = []
        }.disabled(model.isSyncing)
        Text(
          "The level preview contains display readings and meanings for browsing. Demo progress is synthetic. Neither is uploaded or saved over your account cache."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).navigationTitle("Account")
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
            .map { .studying($0, reviewAt: nil, guruAt: nil) } ?? .locked
          return SubjectCatalogItem(subject: value, status: status)
        }.filter { !remaining || ($0.status.stage?.rawValue ?? 0) < 5 })
      level = query.level
    }
  }
}
