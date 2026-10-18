import StudyCore
import StudyPersistence
import StudyUI
import SwiftUI

@MainActor enum StudyAppAssembly {
  static let reviewDefaults: UserDefaults = {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("--review-fixture") {
        let suite = "dev.usagiunagi.mac-review-fixture"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var preferences = ReviewPreferences()
        if arguments.contains("--anki-fixture") {
          preferences.sessionOptions.ankiMode =
            arguments.contains("--reading-anki-fixture") ? .reading : .both
          preferences.sessionOptions.combinedAnki = arguments.contains("--combined-anki-fixture")
          preferences.sessionOptions.groupMeaningReading = true
          preferences.sessionOptions.incorrectAnswerDelay = 0
        }
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "native.reviewPreferences")
        return defaults
      }
    #endif
    return .standard
  }()
  static var isReviewFixture: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--review-fixture")
    #else
      false
    #endif
  }
  static func makeModel() -> StudyAppModel {
    #if DEBUG
      if isReviewFixture {
        return StudyAppModel(
          credentials: FixtureCredentials(), client: fixtureClient,
          openStore: { try await reviewFixtureStore() })
      }
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    return StudyAppModel(
      credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
      legacySnapshotURL: directory.appending(path: "snapshot-v1.json"),
      openStore: { try await StudyStore.open(at: directory.appending(path: "study.store")) })
  }
  #if DEBUG
    private struct FixtureCredentials: StudyCredentialStore {
      func load() -> String? { "fixture" }
      func save(_ token: String) throws { throw StudyStoreError.sampleData }
      func remove() throws { throw StudyStoreError.sampleData }
    }
    private static var fixtureClient: WaniKaniClient {
      WaniKaniClient { request in
        guard request.httpMethod == "GET" else { throw StudyStoreError.sampleData }
        let json: String
        switch request.url?.lastPathComponent {
        case "user":
          json =
            #"{"object":"user","data":{"id":"review-fixture","username":"Synthetic review fixture","level":1,"current_vacation_started_at":null}}"#
        case "study_materials":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":201,"object":"study_material","data":{"subject_id":1,"meaning_note":"Server version of the note.","reading_note":"いち","meaning_synonyms":["Server synonym"]}}]}"#
        case "assignments":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":101,"object":"assignment","data":{"subject_id":1,"subject_type":"kanji","srs_stage":4,"available_at":"2099-01-01T00:00:00Z","started_at":"2020-01-01T00:00:00Z","unlocked_at":"2020-01-01T00:00:00Z","hidden":false}}]}"#
        default: throw StudyStoreError.sampleData
        }
        return (
          Data(json.utf8),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    }
    private static func reviewFixtureStore() async throws -> StudyStore {
      let cache = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      var profile = StudyAccountProfile(username: "Synthetic review fixture")
      profile.level = 1
      profile.maxLevelGranted = 60
      var subject = CatalogSubject(id: 1, kind: .kanji)
      subject.level = 1
      subject.japanese = "一"
      subject.meanings = [.init("One", role: .primary)]
      subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
      if ProcessInfo.processInfo.arguments.contains("--radical-fixture") {
        subject = CatalogSubject(id: 8790, kind: .radical)
        subject.level = 1
        subject.meanings = [.init("Death Star", role: .primary)]
        subject.characterImageURL =
          "https://cdn.wanikani.com/images/363-subject-8790-with-css-original.svg?1520987154"
      }
      var assignment = CatalogAssignment(id: 101, subjectID: subject.id, kind: subject.kind)
      assignment.level = 1
      assignment.srsStage = 3
      assignment.startedAt = 1
      assignment.availableAt = 1
      if ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
        || ProcessInfo.processInfo.arguments.contains("--lesson-fixture")
      {
        assignment.srsStage = 0
        assignment.startedAt = nil
        assignment.availableAt = nil
        assignment.unlockedAt = 1
      }
      var fixture = LegacyStudyExport(schemaVersion: 15, profile: profile)
      if subject.kind == .kanji {
        subject.meaningMnemonic = "A <kanji>single line</kanji> represents <b>one</b>."
        subject.meaningHint = "Count the line: <b>one</b>."
        subject.readingMnemonic = "Read this as <reading>いち</reading>."
        subject.componentSubjectIDs = [2]
        subject.amalgamationSubjectIDs = [3]
        var component = CatalogSubject(id: 2, kind: .radical)
        component.level = 1
        component.japanese = "一"
        component.meanings = [.init("Ground", role: .primary)]
        var vocabulary = CatalogSubject(id: 3, kind: .vocabulary)
        vocabulary.level = 1
        vocabulary.japanese = "一つ"
        vocabulary.meanings = [.init("One thing", role: .primary)]
        vocabulary.readings = [.init("ひとつ", isPrimary: true, kind: .unknown)]
        vocabulary.meaningMnemonic = "A synthetic <vocabulary>vocabulary</vocabulary> example."
        vocabulary.sentences = [.init(japanese: "一つください。", english: "One, please.")]
        vocabulary.componentSubjectIDs = [1]
        fixture.subjects = [subject, component, vocabulary]
        fixture.materials = [
          .init(
            serverID: 0,
            value: .init(
              subjectID: subject.id, meaningNote: "A saved synthetic note.",
              meaningSynonyms: ["Single"]), pending: false, legacyRevision: 0)
        ]
      } else {
        fixture.subjects = [subject]
      }
      if ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") {
        fixture.materials = [
          .init(
            serverID: 201,
            value: .init(
              subjectID: 1, meaningNote: "Local saved note. 🐰\nSecond line.",
              readingNote: "いち", meaningSynonyms: ["Local synonym"]), pending: true,
            legacyRevision: 0)
        ]
      }
      fixture.assignments = [assignment]
      if ProcessInfo.processInfo.arguments.contains("--review-recovery-fixture") {
        let lesson = ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
        fixture.pendingReviews = [
          .init(
            assignment: assignment,
            submission: .init(
              itemID: 0,
              subjectID: subject.id, assignmentID: assignment.id, isLesson: lesson,
              meaningWrong: !lesson, readingWrong: false, meaningWrongCount: lesson ? 0 : 1,
              readingWrongCount: 0, createdAt: 100))
        ]
      }
      _ = try await cache.importLegacyAccount(
        fixture, sourceID: "review-fixture", verifiedAccountID: "review-fixture",
        verifiedUsername: profile.username, credentialID: StudyAppModel.credentialID("fixture"))
      return cache
    }
  #endif
}

struct StudyRoot: View {
  @Bindable var store: StudyAppModel
  @StoredReviewPreferences private var reviewPreferences
  private var preferredAppearance: ColorScheme? {
    if StudyAppAssembly.isReviewFixture {
      if ProcessInfo.processInfo.arguments.contains("--light-fixture") { return .light }
      if ProcessInfo.processInfo.arguments.contains("--dark-fixture") { return .dark }
    }
    return $reviewPreferences.colorScheme
  }
  private enum Destination: String, CaseIterable, Identifiable {
    case reviews = "Reviews"
    case lessons = "Lessons"
    case practice = "Practice"
    case statistics = "Statistics"
    case subjects = "Subjects"
    case settings = "Review settings"
    case savedWork = "Saved work"
    case account = "Account"
    var id: Self { self }
    var symbol: String {
      switch self {
      case .reviews: "rectangle.and.pencil.and.ellipsis"
      case .lessons: "books.vertical"
      case .practice: "square.and.pencil"
      case .statistics: "chart.bar.xaxis"
      case .subjects: "character.book.closed"
      case .settings: "slider.horizontal.3"
      case .savedWork: "tray.and.arrow.up"
      case .account: "person.crop.circle"
      }
    }
  }
  @State private var section: Destination? = .statistics
  @State private var subject: StudySubject?
  @State private var token = ""
  @State private var catalogAnswers = true
  var body: some View {
    NavigationSplitView {
      List(selection: $section) {
        ForEach(Destination.allCases) { section in
          Label(section.rawValue, systemImage: section.symbol).tag(Optional(section))
            .accessibilityIdentifier("navigation.\(section.rawValue)")
        }
      }.navigationTitle(AppIdentity.name).navigationSplitViewColumnWidth(min: 170, ideal: 200)
    } detail: {
      Group {
        if section == .practice {
          KatakanaPracticeView()
        } else if section == .settings {
          ReviewSettingsPanel(
            preferences: reviewPreferences,
            changed: { old, new in
              do { try $reviewPreferences.applyChanges(from: old, to: new) } catch {
                store.error = error.localizedDescription
              }
            }, supportsAudio: false, supportsSessionOptions: true)
        } else if section == .account || store.snapshot == nil {
          account
        } else if let snapshot = store.snapshot {
          if section == .reviews {
            if !snapshot.isSample, let accountID = snapshot.accountID,
              let cache = store.savedWorkStore
            {
              NativeReviewView(store: cache, accountID: accountID).id(accountID)
            } else {
              ContentUnavailableView(
                "Connect to review", systemImage: "rectangle.and.pencil.and.ellipsis",
                description: Text(
                  "Sample statistics do not contain a complete offline review catalog."))
            }
          } else if section == .lessons {
            if !snapshot.isSample, let accountID = snapshot.accountID,
              let cache = store.savedWorkStore
            {
              NativeLessonView(store: cache, accountID: accountID).id(accountID)
            } else {
              ContentUnavailableView(
                "Connect to study lessons", systemImage: "books.vertical",
                description: Text(
                  "Connect and refresh your account to save unlocked lessons on this Mac."))
            }
          } else if section == .savedWork {
            if !snapshot.isSample, let accountID = snapshot.accountID,
              let cache = store.savedWorkStore
            {
              SavedWorkView(
                store: cache, accountID: accountID, isSyncing: store.isSyncing,
                compareSavedWork: store.compareSavedWork
              ) {
                try await store.syncSavedWork(accountID: accountID)
              }.id(accountID)
            } else {
              ContentUnavailableView(
                "No account work in sample mode", systemImage: "tray",
                description: Text(
                  "Connect your account to see work saved on this Mac. The iPhone and iPad queues stay on those devices."
                ))
            }
          } else if section == .subjects {
            if !snapshot.isSample, store.contentAccessVerified, let accountID = snapshot.accountID,
              let cache = store.savedWorkStore
            {
              NativeSubjectCatalogView(
                store: cache, accountID: accountID, maximumLevel: store.maximumContentLevel
              ).id(accountID)
            } else {
              NavigationStack {
                SubjectCatalogView(
                  collection: sampleCatalog(snapshot), title: "Subjects", mode: .all,
                  showAnswers: $catalogAnswers, maximumLevel: store.maximumContentLevel
                ) { id in
                  subject = snapshot.subjects.first { $0.id == id }
                }
              }
            }
          } else {
            StudyDashboard(snapshot: snapshot) { id in
              subject = snapshot.subjects.first { $0.id == id }
            }
          }
        }
      }.navigationTitle(section?.rawValue ?? "Statistics")
        .toolbar {
          if store.isSyncing { ProgressView().controlSize(.small) }
          Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
            .disabled(store.isSyncing || store.snapshot?.isSample != false)
        }
        .safeAreaInset(edge: .bottom) {
          if [.reviews, .lessons].contains(section),
            store.snapshot?.requiresAssignmentRefresh == true
          {
            Label(
              "Refresh WaniKani to reload progress for archived answers.",
              systemImage: "arrow.clockwise"
            )
            .font(.callout).padding()
          }
          if StudyAppAssembly.isReviewFixture {
            Text("Synthetic review fixture · memory only · uploads disabled").font(.caption)
              .padding()
          }
          if let error = store.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding().frame(
              maxWidth: .infinity
            ).background(.regularMaterial)
          }
          if section == .savedWork, let summary = store.syncSummary {
            Text(summary).font(.callout).padding().frame(maxWidth: .infinity).background(
              .regularMaterial)
          }
        }
    }.preferredColorScheme(preferredAppearance)
      .onChange(of: section) { _, _ in Task { await store.reloadSavedSnapshot() } }
      .sheet(item: $subject) { item in
        if let accountID = store.snapshot?.accountID, let cache = store.savedWorkStore,
          store.snapshot?.isSample == false
        {
          NavigationStack {
            NativeSubjectDetailsView(store: cache, accountID: accountID, subjectID: item.id)
              .navigationTitle("Subject")
          }.toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { subject = nil } }
          }
          .id(accountID).frame(minWidth: 480, minHeight: 520)
        } else {
          NativeSubjectDetail(
            subject: item, maximumLevel: store.maximumContentLevel,
            accessVerified: store.contentAccessVerified)
        }
      }
  }
  private func sampleCatalog(_ snapshot: StudySnapshot) -> SubjectCatalogCollection {
    let assignments = Dictionary(
      snapshot.assignments.map { ($0.subjectID, $0.srsStageNumber) }, uniquingKeysWith: max)
    return SubjectCatalogCollection(
      items: snapshot.subjects.filter { $0.level <= store.maximumContentLevel }.map { item in
        var value = CatalogSubject(id: item.id, kind: item.kind)
        value.japanese = item.characters
        value.level = item.level
        value.meanings = [.init(item.meaning, role: .primary)]
        value.readings = item.readings.map { .init($0, isPrimary: true, kind: .unknown) }
        let status: SubjectCatalogItem.Status =
          assignments[item.id].flatMap(StudySRSStage.init(rawValue:)).map {
            .studying($0, reviewAt: nil, guruAt: nil)
          } ?? .unassigned
        return SubjectCatalogItem(subject: value, status: status)
      })
  }
  private var account: some View {
    Form {
      Section("WaniKani account") {
        Text(
          "Native Mac statistics, subject browsing, lessons and saved offline reviews. Full study settings are still being migrated."
        ).foregroundStyle(.secondary)
        StudyTokenEntry(token: $token)
        Text(
          "Connect and refresh use reading access. Sending from Saved work also requires the corresponding review, assignment or study-material write permissions. The token stays in this Mac's Keychain; saved work stays on this device."
        ).font(.caption).foregroundStyle(.secondary)
        Button("Connect and sync") {
          Task {
            if await store.connect(token) {
              token = ""
              section = .statistics
            }
          }
        }.disabled(store.isSyncing || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let snapshot = store.snapshot, !snapshot.isSample {
          LabeledContent("Connected", value: snapshot.username)
          if store.contentAccessVerified {
            LabeledContent("Content access", value: "Through level \(store.maximumContentLevel)")
          } else {
            Text("Refresh to verify your WaniKani content access.").foregroundStyle(.secondary)
          }
          Button("Disconnect and remove local snapshot", role: .destructive) {
            Task { await store.disconnect() }
          }.disabled(store.isDisconnecting)
        }
      }
      Section("Explore") {
        Button("Preview free levels 1–3") {
          store.loadSample(freeLevels: true)
          section = .subjects
        }.disabled(store.isSyncing)
        Button("Use sample data") {
          store.loadSample()
          section = .statistics
        }.disabled(store.isSyncing)
        Text(
          "The level preview contains display readings and meanings for browsing. Demo progress is synthetic. Neither is uploaded or saved over your account cache."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped)
  }
}

private struct NativeSubjectDetail: View {
  let subject: StudySubject
  let maximumLevel: Int
  let accessVerified: Bool
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        if subject.level > maximumLevel {
          ContentUnavailableView(
            "Subscription level limit", systemImage: "lock",
            description: Text(
              accessVerified
                ? "Your WaniKani subscription allows content through level \(maximumLevel)."
                : "Refresh your account to verify access to this level."))
        } else {
          Text(subject.characters.isEmpty ? subject.meaning : subject.characters).font(.largeTitle)
            .foregroundStyle(subject.kind == .kanji ? StudyPalette.kanji : StudyPalette.vocabulary)
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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }.frame(minWidth: 420, minHeight: 320)
  }
}
