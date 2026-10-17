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
    var maximumContentLevel: Int { snapshot?.isSample == true ? 60 : profile?.maxLevelGranted ?? 3 }
    var contentAccessVerified: Bool { snapshot?.isSample == true || profile != nil }
    var error: String?
    var isSyncing = false
    @ObservationIgnored private var restored = false
    private let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    @ObservationIgnored private var persistence: Task<StudyStore, any Error>?
    private func repository() async throws -> StudyStore {
        let task = persistence ?? Task { try await StudyStore.open(at: directory.appending(path: "study.store")) }
        persistence = task
        do { return try await task.value }
        catch { persistence = nil; throw error }
    }
    private let reader = WaniKaniClient()

    func restore() async {
        guard !restored else { return }; restored = true
        if ProcessInfo.processInfo.arguments.contains("SampleData") { loadSample(); return }
        isSyncing = true; defer { isSyncing = false }
        do {
            if let token = try TokenKeychain.load() {
                let cache = try await repository(), credential = credentialID(token)
                if try await cache.snapshot(credentialID: credential) == nil {
                    try await cache.importLegacySnapshot(at: directory.appending(path: "snapshot-v1.json"), credentialID: credential)
                }
                let restoredSnapshot = try await cache.snapshot(credentialID: credential)
                if let accountID = restoredSnapshot?.accountID { profile = try await cache.accountState(accountID: accountID)?.profile }
                snapshot = restoredSnapshot
            }
        } catch { self.error = "Couldn't read saved statistics: \(error.localizedDescription)" }
    }
    func loadSample() {
        guard !isSyncing else { return }
        do { snapshot = try .sample(); profile = nil; error = nil } catch { self.error = error.localizedDescription }
    }
    func connect(_ token: String) async {
        guard !isSyncing else { return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { error = "Enter your WaniKani API token."; return }
        isSyncing = true; error = nil; defer { isSyncing = false }
        do {
            let previous = try TokenKeychain.load().map(credentialID)
            let credential = credentialID(token)
            let cache = try await repository()
            let newSnapshot = try await cache.refresh(credentialID: credential, token: token, client: reader)
            guard let accountID = newSnapshot.accountID else { throw StudyStoreError.invalidIdentity }
            let newProfile = try await cache.accountState(accountID: accountID)?.profile
            try TokenKeychain.save(token)
            profile = newProfile; snapshot = newSnapshot
            if let previous, previous != credential { try await cache.removeSnapshot(credentialID: previous) }
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        do {
            guard let token = try TokenKeychain.load() else { error = "Connect a WaniKani account first."; return }
            await connect(token)
        } catch { self.error = error.localizedDescription }
    }
    private func credentialID(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func disconnect() async {
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            if let token = try TokenKeychain.load() {
                let cache = try await repository()
                await cache.cancelSynchronization()
                try await cache.removeSnapshot(credentialID: credentialID(token))
            }
            let legacy = directory.appending(path: "snapshot-v1.json")
            if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
            try TokenKeychain.remove(); snapshot = nil; profile = nil; error = nil
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
        case statistics = "Statistics", subjects = "Subjects", account = "Account"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .statistics: "chart.bar.xaxis"
            case .subjects: "character.book.closed"
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
                    if section == .subjects {
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
                }
        }.sheet(item: $subject) { NativeSubjectDetail(subject: $0, maximumLevel: store.maximumContentLevel, accessVerified: store.contentAccessVerified) }
    }
    private var account: some View {
        Form {
            Section("WaniKani account") {
                Text("Native Mac statistics and subject browsing. Reviews and lessons still run in the iPhone/iPad app while their session UI is migrated.").foregroundStyle(.secondary)
                SecureField("API token", text: $token)
                Link("Create a token in WaniKani", destination: URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
                Text("Only reading access is used. The token is stored in this Mac's Keychain; the account snapshot stays locally for offline access.").font(.caption).foregroundStyle(.secondary)
                Button("Connect and sync") { Task { await store.connect(token); if store.error == nil { token = ""; section = .statistics } } }.disabled(store.isSyncing || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let snapshot = store.snapshot, !snapshot.isSample {
                    LabeledContent("Connected", value: snapshot.username)
                    if store.contentAccessVerified {
                        LabeledContent("Content access", value: "Through level \(store.maximumContentLevel)")
                    } else {
                        Text("Refresh to verify your WaniKani content access.").foregroundStyle(.secondary)
                    }
                    Button("Disconnect and remove local snapshot", role: .destructive) { Task { await store.disconnect() } }.disabled(store.isSyncing)
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
