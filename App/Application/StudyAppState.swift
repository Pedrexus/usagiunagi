import SwiftUI
import Observation
import Security
import CryptoKit
import StudyCore
import StudyPersistence
import StudyUI


@MainActor @Observable
final class StudyAppState {
    static let reviewDefaults: UserDefaults = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--review-fixture") {
            let suite = "dev.usagiunagi.mac-review-fixture"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            var preferences = ReviewPreferences()
            if arguments.contains("--anki-fixture") {
                preferences.sessionOptions.ankiMode = arguments.contains("--reading-anki-fixture") ? .reading : .both
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
    var snapshot: StudySnapshot?
    var profile: StudyAccountProfile?
    var savedWorkStore: StudyStore?
    var syncSummary: String?
    var maximumContentLevel: Int { snapshot?.isSample == true ? 60 : profile?.maxLevelGranted ?? 3 }
    var contentAccessVerified: Bool { snapshot?.isSample == true || profile != nil }
    var error: String?
    var isDisconnecting = false
    var isReviewFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--review-fixture")
        #else
        false
        #endif
    }
    var isSyncing: Bool { activeRequests > 0 || isDisconnecting }
    private var activeRequests = 0
    @ObservationIgnored private var activeCredential: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var restored = false
    private let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    @ObservationIgnored private var persistence: Task<StudyStore, any Error>?
    private let reader = WaniKaniClient()

    private func repository() async throws -> StudyStore {
        let task = persistence ?? Task { try await StudyStore.open(at: directory.appending(path: "study.store")) }
        persistence = task
        do { let store = try await task.value; savedWorkStore = store; return store }
        catch { persistence = nil; throw error }
    }
    private func beginRequest(credential: String?) throws {
        guard !isDisconnecting, activeRequests == 0 || activeCredential == credential else {
            throw StudyUploadError.alreadyRunning
        }
        activeCredential = credential; activeRequests += 1
    }
    private func finishRequest(_ epoch: UUID) {
        guard generation == epoch else { return }
        activeRequests -= 1
        if activeRequests == 0 { activeCredential = nil }
    }
    private func checkRequest(_ epoch: UUID) throws {
        guard generation == epoch else { throw CancellationError() }
    }
    func restore() async {
        guard !restored else { return }; restored = true
        #if DEBUG
        if isReviewFixture {
            do { try await restoreReviewFixture() } catch { self.error = error.localizedDescription }
            return
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--sample-data") { loadSample(); return }
        let epoch = generation
        do {
            try beginRequest(credential: nil); defer { finishRequest(epoch) }
            if let token = try TokenKeychain.load() {
                let cache = try await repository(), credential = credentialID(token)
                try checkRequest(epoch)
                let cached = try await cache.snapshot(credentialID: credential)
                try checkRequest(epoch)
                if cached == nil {
                    try await cache.importLegacySnapshot(at: directory.appending(path: "snapshot-v1.json"), credentialID: credential)
                }
                let restoredSnapshot = try await cache.snapshot(credentialID: credential)
                let restoredProfile: StudyAccountProfile?
                if let accountID = restoredSnapshot?.accountID {
                    restoredProfile = try await cache.accountState(accountID: accountID)?.profile
                } else { restoredProfile = nil }
                try checkRequest(epoch)
                snapshot = restoredSnapshot; profile = restoredProfile
            }
        } catch {
            if generation == epoch { self.error = "Couldn't read saved statistics: \(error.localizedDescription)" }
        }
    }
    func reloadSavedSnapshot() async {
        guard !isSyncing, let accountID = snapshot?.accountID, let cache = savedWorkStore else { return }
        let epoch = generation
        do {
            let credential = isReviewFixture ? "review-fixture" : try TokenKeychain.load().map(credentialID)
            guard let credential else { return }
            let saved = try await cache.snapshot(credentialID: credential)
            try checkRequest(epoch)
            guard saved?.accountID == accountID, snapshot?.accountID == accountID else { return }
            snapshot = saved
        } catch { if generation == epoch { self.error = error.localizedDescription } }
    }
    func loadSample(freeLevels: Bool = false) {
        guard !isSyncing else { return }
        do { snapshot = try (freeLevels ? StudySnapshot.freeLevelsPreview() : StudySnapshot.sample()); profile = nil; error = nil; syncSummary = nil }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult func connect(_ token: String) async -> Bool {
        guard !isReviewFixture else { return false }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { error = "Enter your WaniKani API token."; return false }
        let epoch = generation, credential = credentialID(token)
        do {
            try beginRequest(credential: credential); defer { finishRequest(epoch) }
            error = nil; syncSummary = nil
            let previous = try TokenKeychain.load().map(credentialID)
            let cache = try await repository()
            try checkRequest(epoch)
            let result = try await cache.synchronize(credentialID: credential, token: token, client: reader)
            try checkRequest(epoch)
            try TokenKeychain.save(token)
            profile = result.profile; snapshot = result.snapshot
            if let previous, previous != credential { try await cache.removeSnapshot(credentialID: previous) }
            try checkRequest(epoch)
            return true
        } catch {
            if generation == epoch, !(error is CancellationError) { self.error = error.localizedDescription }
            return false
        }
    }
    func refresh() async {
        guard !isReviewFixture else { return }
        do {
            guard let token = try TokenKeychain.load() else { error = "Connect a WaniKani account first."; return }
            await connect(token)
        } catch { self.error = error.localizedDescription }
    }
    /// Sending is an explicit Saved work action; ordinary refresh remains read-only.
    func syncSavedWork(accountID: String) async throws {
        guard !isReviewFixture else { throw StudyStoreError.sampleData }
        guard snapshot?.accountID == accountID, snapshot?.isSample == false,
              let token = try TokenKeychain.load() else { throw StudyStoreError.invalidIdentity }
        let epoch = generation, credential = credentialID(token)
        try beginRequest(credential: credential); defer { finishRequest(epoch) }
        error = nil; syncSummary = nil
        let cache = try await repository()
        try checkRequest(epoch)
        do {
            let result = try await cache.synchronize(.sendSavedWork(accountID: accountID), credentialID: credential, token: token, client: reader)
            try checkRequest(epoch)
            snapshot = result.snapshot; profile = result.profile
            if let report = result.upload { syncSummary = summary(report) }
        } catch let failure as StudySynchronizationFailure {
            try checkRequest(epoch)
            syncSummary = summary(failure.upload)
            throw failure
        }
    }
    private func summary(_ report: StudyUploadReport) -> String {
        "Sent \(report.uploadedReviews) reviews, \(report.uploadedLessons) lessons and \(report.uploadedMaterials) note edits. \(report.reviewsNeedingAttention + report.materialsNeedingAttention) items need attention."
            + (report.onVacation ? " Reviews and lessons are paused during vacation." : "")
    }
    func compareSavedWork(_ request: StudyRecoveryRequest) async throws -> StudyRecoveryComparison {
        #if DEBUG
        if isReviewFixture, ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") || ProcessInfo.processInfo.arguments.contains("--review-recovery-fixture") {
            guard request.accountID == "review-fixture", let cache = savedWorkStore else { throw StudyStoreError.sampleData }
            let client = WaniKaniClient { request in
                guard request.httpMethod == "GET" else { throw StudyStoreError.sampleData }
                let json: String
                switch request.url?.lastPathComponent {
                case "user":
                    json = #"{"object":"user","data":{"id":"review-fixture","username":"Synthetic review fixture","level":1,"current_vacation_started_at":null}}"#
                case "study_materials":
                    json = #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":201,"object":"study_material","data":{"subject_id":1,"meaning_note":"Server version of the note.","reading_note":"いち","meaning_synonyms":["Server synonym"]}}]}"#
                case "assignments":
                    json = #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":101,"object":"assignment","data":{"subject_id":1,"subject_type":"kanji","srs_stage":4,"available_at":"2099-01-01T00:00:00Z","started_at":"2020-01-01T00:00:00Z","unlocked_at":"2020-01-01T00:00:00Z","hidden":false}}]}"#
                default: throw StudyStoreError.sampleData
                }
                return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return try await cache.compareSavedWork(request, credentialID: "review-fixture", token: "fixture", client: client)
        }
        #endif
        guard !isReviewFixture, snapshot?.isSample == false,
              snapshot?.accountID == request.accountID,
              let token = try TokenKeychain.load() else { throw StudyStoreError.invalidIdentity }
        let epoch = generation, credential = credentialID(token)
        try beginRequest(credential: credential); defer { finishRequest(epoch) }
        let cache = try await repository()
        try checkRequest(epoch)
        let comparison = try await cache.compareSavedWork(request, credentialID: credential, token: token, client: reader)
        try checkRequest(epoch)
        return comparison
    }
    #if DEBUG
    private func restoreReviewFixture() async throws {
        let cache = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
        var profile = StudyAccountProfile(username: "Synthetic review fixture")
        profile.level = 1; profile.maxLevelGranted = 60
        var subject = CatalogSubject(id: 1, kind: .kanji)
        subject.level = 1; subject.japanese = "一"
        subject.meanings = [.init("One", role: .primary)]
        subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
        if ProcessInfo.processInfo.arguments.contains("--radical-fixture") {
            subject = CatalogSubject(id: 8790, kind: .radical)
            subject.level = 1; subject.meanings = [.init("Death Star", role: .primary)]
            subject.characterImageURL = "https://cdn.wanikani.com/images/363-subject-8790-with-css-original.svg?1520987154"
        }
        var assignment = CatalogAssignment(id: 101, subjectID: subject.id, kind: subject.kind)
        assignment.level = 1; assignment.srsStage = 3; assignment.startedAt = 1; assignment.availableAt = 1
        if ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture") || ProcessInfo.processInfo.arguments.contains("--lesson-fixture") {
            assignment.srsStage = 0; assignment.startedAt = nil; assignment.availableAt = nil; assignment.unlockedAt = 1
        }
        var fixture = LegacyStudyExport(schemaVersion: 15, profile: profile)
        if subject.kind == .kanji {
            subject.meaningMnemonic = "A <kanji>single line</kanji> represents <b>one</b>."
            subject.meaningHint = "Count the line: <b>one</b>."
            subject.readingMnemonic = "Read this as <reading>いち</reading>."
            subject.componentSubjectIDs = [2]; subject.amalgamationSubjectIDs = [3]
            var component = CatalogSubject(id: 2, kind: .radical)
            component.level = 1; component.japanese = "一"; component.meanings = [.init("Ground", role: .primary)]
            var vocabulary = CatalogSubject(id: 3, kind: .vocabulary)
            vocabulary.level = 1; vocabulary.japanese = "一つ"; vocabulary.meanings = [.init("One thing", role: .primary)]
            vocabulary.readings = [.init("ひとつ", isPrimary: true, kind: .unknown)]
            vocabulary.meaningMnemonic = "A synthetic <vocabulary>vocabulary</vocabulary> example."
            vocabulary.sentences = [.init(japanese: "一つください。", english: "One, please.")]
            vocabulary.componentSubjectIDs = [1]
            fixture.subjects = [subject, component, vocabulary]
            fixture.materials = [.init(serverID: 0, value: .init(subjectID: subject.id, meaningNote: "A saved synthetic note.", meaningSynonyms: ["Single"]), pending: false, legacyRevision: 0)]
        } else { fixture.subjects = [subject] }
        if ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") {
            fixture.materials = [.init(serverID: 201,
                value: .init(subjectID: 1, meaningNote: "Local saved note. 🐰\nSecond line.",
                             readingNote: "いち", meaningSynonyms: ["Local synonym"]), pending: true, legacyRevision: 0)]
        }
        fixture.assignments = [assignment]
        if ProcessInfo.processInfo.arguments.contains("--review-recovery-fixture") {
            let lesson = ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
            fixture.pendingReviews = [.init(assignment: assignment, submission: .init(itemID: 0,
                subjectID: subject.id, assignmentID: assignment.id, isLesson: lesson,
                meaningWrong: !lesson, readingWrong: false, meaningWrongCount: lesson ? 0 : 1,
                readingWrongCount: 0, createdAt: 100))]
        }
        _ = try await cache.importLegacyAccount(fixture, sourceID: "review-fixture", verifiedAccountID: "review-fixture",
            verifiedUsername: profile.username, credentialID: "review-fixture")
        persistence = Task { cache }; savedWorkStore = cache; self.profile = profile
        snapshot = try await cache.snapshot(credentialID: "review-fixture")
    }
    #endif

    private func credentialID(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func disconnect() async {
        guard !isReviewFixture else { return }
        guard !isDisconnecting else { return }
        let connectingCredential = activeCredential
        generation = UUID(); activeRequests = 0; activeCredential = nil
        isDisconnecting = true; defer { isDisconnecting = false }
        do {
            let cache = try await repository()
            await cache.cancelSynchronization()
            let savedCredential = try TokenKeychain.load().map(credentialID)
            for credential in Set([connectingCredential, savedCredential].compactMap({ $0 })) {
                try await cache.removeSnapshot(credentialID: credential)
            }
            let legacy = directory.appending(path: "snapshot-v1.json")
            if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
            try TokenKeychain.remove(); snapshot = nil; profile = nil; error = nil; syncSummary = nil
        } catch { self.error = error.localizedDescription }
    }
}

private enum TokenKeychain {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TsurukameNative.WaniKani", kSecAttrAccount as String: "api-token"] }
    static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    static func load() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; try check(status)
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return token
    }
    static func save(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { var q = query; q.merge(attributes) { _, new in new }; try check(SecItemAdd(q as CFDictionary, nil)) }
        else { try check(status) }
    }
    static func remove() throws { let status = SecItemDelete(query as CFDictionary); if status != errSecItemNotFound { try check(status) } }
}

struct StudyRoot: View {
    @Bindable var store: StudyAppState
    @StoredReviewPreferences private var reviewPreferences
    private var preferredAppearance: ColorScheme? {
        if store.isReviewFixture {
            if ProcessInfo.processInfo.arguments.contains("--light-fixture") { return .light }
            if ProcessInfo.processInfo.arguments.contains("--dark-fixture") { return .dark }
        }
        return $reviewPreferences.colorScheme
    }
    private enum Destination: String, CaseIterable, Identifiable {
        case reviews = "Reviews", lessons = "Lessons", practice = "Practice", statistics = "Statistics", subjects = "Subjects", settings = "Review settings", savedWork = "Saved work", account = "Account"
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
                    Label(section.rawValue, systemImage: section.symbol).tag(Optional(section)).accessibilityIdentifier("navigation.\(section.rawValue)")
                }
            }.navigationTitle(AppIdentity.name).navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            Group {
                if section == .practice { KatakanaPracticeView() }
                else if section == .settings {
                    ReviewSettingsPanel(preferences: reviewPreferences, changed: { old, new in
                        do { try $reviewPreferences.applyChanges(from: old, to: new) }
                        catch { store.error = error.localizedDescription }
                    }, supportsAudio: false, supportsSessionOptions: true)
                }
                else if section == .account || store.snapshot == nil { account }
                else if let snapshot = store.snapshot {
                    if section == .reviews {
                        if !snapshot.isSample, let accountID = snapshot.accountID, let cache = store.savedWorkStore {
                            NativeReviewView(store: cache, accountID: accountID).id(accountID)
                        } else {
                            ContentUnavailableView("Connect to review", systemImage: "rectangle.and.pencil.and.ellipsis", description: Text("Sample statistics do not contain a complete offline review catalog."))
                        }
                    } else if section == .lessons {
                        if !snapshot.isSample, let accountID = snapshot.accountID, let cache = store.savedWorkStore {
                            NativeLessonView(store: cache, accountID: accountID).id(accountID)
                        } else {
                            ContentUnavailableView("Connect to study lessons", systemImage: "books.vertical", description: Text("Connect and refresh your account to save unlocked lessons on this Mac."))
                        }
                    } else if section == .savedWork {
                        if !snapshot.isSample, let accountID = snapshot.accountID, let cache = store.savedWorkStore {
                            SavedWorkView(store: cache, accountID: accountID, isSyncing: store.isSyncing,
                                          compareSavedWork: store.compareSavedWork) {
                                try await store.syncSavedWork(accountID: accountID)
                            }.id(accountID)
                        } else {
                            ContentUnavailableView("No account work in sample mode", systemImage: "tray",
                                description: Text("Connect your account to see work saved on this Mac. The iPhone and iPad queues stay on those devices."))
                        }
                    } else if section == .subjects {
                        if !snapshot.isSample, store.contentAccessVerified, let accountID = snapshot.accountID, let cache = store.savedWorkStore {
                            NativeSubjectCatalogView(store: cache, accountID: accountID, maximumLevel: store.maximumContentLevel).id(accountID)
                        } else {
                            NavigationStack {
                                SubjectCatalogView(collection: sampleCatalog(snapshot), title: "Subjects", mode: .all,
                                    showAnswers: $catalogAnswers, maximumLevel: store.maximumContentLevel) { id in
                                    subject = snapshot.subjects.first { $0.id == id }
                                }
                            }
                        }
                    } else { StudyDashboard(snapshot: snapshot) { id in subject = snapshot.subjects.first { $0.id == id } } }
                }
            }.navigationTitle(section?.rawValue ?? "Statistics")
                .toolbar {
                    if store.isSyncing { ProgressView().controlSize(.small) }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isSyncing || store.snapshot?.isSample != false)
                }
                .safeAreaInset(edge: .bottom) {
                    if [.reviews, .lessons].contains(section), store.snapshot?.requiresAssignmentRefresh == true {
                        Label("Refresh WaniKani to reload progress for archived answers.", systemImage: "arrow.clockwise")
                            .font(.callout).padding()
                    }
                    if store.isReviewFixture { Text("Synthetic review fixture · memory only · uploads disabled").font(.caption).padding() }
                    if let error = store.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
                    if section == .savedWork, let summary = store.syncSummary {
                        Text(summary).font(.callout).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
        }.preferredColorScheme(preferredAppearance)
        .onChange(of: section) { _, _ in Task { await store.reloadSavedSnapshot() } }
        .sheet(item: $subject) { item in
            if let accountID = store.snapshot?.accountID, let cache = store.savedWorkStore, store.snapshot?.isSample == false {
                NavigationStack {
                    NativeSubjectDetailsView(store: cache, accountID: accountID, subjectID: item.id)
                        .navigationTitle("Subject")
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { subject = nil } } }
                .id(accountID).frame(minWidth: 480, minHeight: 520)
            } else {
                NativeSubjectDetail(subject: item, maximumLevel: store.maximumContentLevel, accessVerified: store.contentAccessVerified)
            }
        }
    }
    private func sampleCatalog(_ snapshot: StudySnapshot) -> SubjectCatalogCollection {
        let assignments = Dictionary(snapshot.assignments.map { ($0.subjectID, $0.srsStageNumber) }, uniquingKeysWith: max)
        return SubjectCatalogCollection(items: snapshot.subjects.filter { $0.level <= store.maximumContentLevel }.map { item in
            var value = CatalogSubject(id: item.id, kind: item.kind)
            value.japanese = item.characters; value.level = item.level
            value.meanings = [.init(item.meaning, role: .primary)]
            value.readings = item.readings.map { .init($0, isPrimary: true, kind: .unknown) }
            let status: SubjectCatalogItem.Status = assignments[item.id].flatMap(StudySRSStage.init(rawValue:)).map { .studying($0, reviewAt: nil, guruAt: nil) } ?? .unassigned
            return SubjectCatalogItem(subject: value, status: status)
        })
    }
    private var account: some View {
        Form {
            Section("WaniKani account") {
                Text("Native Mac statistics, subject browsing, lessons and saved offline reviews. Full study settings are still being migrated.").foregroundStyle(.secondary)
                StudyTokenEntry(token: $token)
                Text("Connect and refresh use reading access. Sending from Saved work also requires the corresponding review, assignment or study-material write permissions. The token stays in this Mac's Keychain; saved work stays on this device.").font(.caption).foregroundStyle(.secondary)
                Button("Connect and sync") { Task { if await store.connect(token) { token = ""; section = .statistics } } }.disabled(store.isSyncing || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let snapshot = store.snapshot, !snapshot.isSample {
                    LabeledContent("Connected", value: snapshot.username)
                    if store.contentAccessVerified {
                        LabeledContent("Content access", value: "Through level \(store.maximumContentLevel)")
                    } else {
                        Text("Refresh to verify your WaniKani content access.").foregroundStyle(.secondary)
                    }
                    Button("Disconnect and remove local snapshot", role: .destructive) { Task { await store.disconnect() } }.disabled(store.isDisconnecting)
                }
            }
            Section("Explore") {
                Button("Preview free levels 1–3") { store.loadSample(freeLevels: true); section = .subjects }.disabled(store.isSyncing)
                Button("Use sample data") { store.loadSample(); section = .statistics }.disabled(store.isSyncing)
                Text("The level preview contains display readings and meanings for browsing. Demo progress is synthetic. Neither is uploaded or saved over your account cache.").font(.caption).foregroundStyle(.secondary)
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
                    ContentUnavailableView("Subscription level limit", systemImage: "lock",
                        description: Text(accessVerified ? "Your WaniKani subscription allows content through level \(maximumLevel)." : "Refresh your account to verify access to this level."))
                } else {
                    Text(subject.characters.isEmpty ? subject.meaning : subject.characters).font(.largeTitle)
                        .foregroundStyle(subject.kind == .kanji ? StudyPalette.kanji : StudyPalette.vocabulary)
                    LabeledContent("Meaning", value: subject.meaning)
                    LabeledContent("Readings", value: subject.readings.isEmpty ? "None" : subject.readings.joined(separator: " · "))
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
