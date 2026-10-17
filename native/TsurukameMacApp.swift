import SwiftUI
import Observation
import Security
import CryptoKit
import StudyCore
import StudyPersistence
import StudyUI

@main
struct TsurukameMacApp: App {
    @State private var store = MacStudyStore()
    var body: some Scene {
        WindowGroup {
            MacStudyRoot(store: store).frame(minWidth: 640, minHeight: 500).task { await store.restore() }
        }.defaultSize(width: 1120, height: 800)
            .commands { CommandGroup(after: .newItem) { Button("Refresh WaniKani") { Task { await store.refresh() } }.keyboardShortcut("r").disabled(store.isSyncing || store.snapshot?.isSample != false) } }
    }
}

@MainActor @Observable
final class MacStudyStore {
    var snapshot: StudySnapshot?
    var profile: StudyAccountProfile?
    var savedWorkStore: StudyStore?
    var syncSummary: String?
    var maximumContentLevel: Int { snapshot?.isSample == true ? 60 : profile?.maxLevelGranted ?? 3 }
    var contentAccessVerified: Bool { snapshot?.isSample == true || profile != nil }
    var error: String?
    var isDisconnecting = false
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
        if ProcessInfo.processInfo.arguments.contains("SampleData") { loadSample(); return }
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
    func loadSample() {
        guard !isSyncing else { return }
        do { snapshot = try .sample(); profile = nil; error = nil; syncSummary = nil }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult func connect(_ token: String) async -> Bool {
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
        do {
            guard let token = try TokenKeychain.load() else { error = "Connect a WaniKani account first."; return }
            await connect(token)
        } catch { self.error = error.localizedDescription }
    }
    /// Sending is an explicit Saved work action; ordinary refresh remains read-only.
    func syncSavedWork(accountID: String) async throws {
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
    private func credentialID(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func disconnect() async {
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

private struct MacStudyRoot: View {
    @Bindable var store: MacStudyStore
    private enum Destination: String, CaseIterable, Identifiable {
        case statistics = "Statistics", subjects = "Subjects", savedWork = "Saved work", account = "Account"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .statistics: "chart.bar.xaxis"
            case .subjects: "character.book.closed"
            case .savedWork: "tray.and.arrow.up"
            case .account: "person.crop.circle"
            }
        }
    }
    @State private var section = Destination.statistics
    @State private var subject: StudySubject?
    @State private var token = ""
    @State private var search = ""
    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(Destination.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                }
            }.navigationTitle(AppIdentity.name).navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            Group {
                if section == .account || store.snapshot == nil { account }
                else if let snapshot = store.snapshot {
                    if section == .savedWork {
                        if !snapshot.isSample, let accountID = snapshot.accountID, let cache = store.savedWorkStore {
                            SavedWorkView(store: cache, accountID: accountID, isSyncing: store.isSyncing) {
                                try await store.syncSavedWork(accountID: accountID)
                            }.id(accountID)
                        } else {
                            ContentUnavailableView("No account work in sample mode", systemImage: "tray",
                                description: Text("Connect your account to see work saved on this Mac. The iPhone and iPad queues stay on those devices."))
                        }
                    } else if section == .subjects {
                        List(snapshot.subjects.filter { $0.level <= store.maximumContentLevel && (search.isEmpty || $0.characters.localizedStandardContains(search) || $0.meaning.localizedStandardContains(search)) }) { item in
                            Button { subject = item } label: {
                                LabeledContent(item.characters.isEmpty ? item.meaning : item.characters, value: "Level \(item.level) · \(item.meaning)")
                            }.buttonStyle(.plain)
                        }.searchable(text: $search, prompt: "Kanji, vocabulary or meaning")
                    } else { StudyDashboard(snapshot: snapshot) { id in subject = snapshot.subjects.first { $0.id == id } } }
                }
            }.navigationTitle(section.rawValue)
                .toolbar {
                    if store.isSyncing { ProgressView().controlSize(.small) }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isSyncing || store.snapshot?.isSample != false)
                }
                .safeAreaInset(edge: .bottom) {
                    if let error = store.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
                    if section == .savedWork, let summary = store.syncSummary {
                        Text(summary).font(.callout).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
        }.sheet(item: $subject) { NativeSubjectDetail(subject: $0, maximumLevel: store.maximumContentLevel, accessVerified: store.contentAccessVerified) }
    }
    private var account: some View {
        Form {
            Section("WaniKani account") {
                Text("Native Mac statistics and subject browsing. Reviews and lessons still run in the iPhone/iPad app while their session UI is migrated.").foregroundStyle(.secondary)
                SecureField("API token", text: $token)
                Link("Create a token in WaniKani", destination: URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
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
                Button("Use sample data") { store.loadSample(); section = .statistics }.disabled(store.isSyncing)
                Text("Sample data is synthetic and clearly labelled. It is never uploaded or saved over your account cache.").font(.caption).foregroundStyle(.secondary)
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
