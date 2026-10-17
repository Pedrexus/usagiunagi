import SwiftUI
import StudyCore
import StudyPersistence

/// Shared native recovery UI. The host owns credentials and synchronization lifetime.
public struct SavedWorkView: View {
    private let store: StudyStore
    private let accountID: String
    private let isSyncing: Bool
    private let synchronize: @MainActor () async throws -> Void
    @State private var work: SavedStudyWork?
    @State private var error: String?
    @State private var performingAction = false

    public init(store: StudyStore, accountID: String, isSyncing: Bool,
                synchronize: @escaping @MainActor () async throws -> Void) {
        self.store = store; self.accountID = accountID; self.isSyncing = isSyncing; self.synchronize = synchronize
    }

    public var body: some View {
        Form {
            Section {
                Text("Completed answers and note edits stay on this device until WaniKani accepts them.")
                    .foregroundStyle(.secondary)
                if let work {
                    LabeledContent("Answers waiting", value: String(work.reviews.count))
                    LabeledContent("Note edits waiting", value: String(work.materials.count))
                    if let retryAt = work.retryAt, retryAt > .now {
                        Text("WaniKani asked us to wait until \(retryAt.formatted(date: .omitted, time: .standard)).")
                    }
                    Button("Sync saved work", systemImage: "arrow.triangle.2.circlepath") {
                        run { try await synchronize() }
                    }.disabled(work.isEmpty || isSyncing || performingAction)
                    Text("Sync checks this account before sending eligible items. Uncertain or changed assignments remain saved for attention.")
                        .font(.caption).foregroundStyle(.secondary)
                    if work.isEmpty {
                        Label("No saved work waiting", systemImage: "checkmark.circle")
                    }
                } else if error == nil { ProgressView("Loading saved work") }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Button("Reload saved work", systemImage: "arrow.clockwise") { run {} }
                    .disabled(isSyncing || performingAction)
            }
            if let work {
                if !work.reviews.isEmpty {
                    Section("Answers") {
                        ForEach(work.reviews, id: \.revision) { review in
                            DisclosureGroup(title(review.subjectID)) {
                                LabeledContent("Type", value: review.submission.isLesson ? "Lesson" : "Review")
                                LabeledContent("Assignment", value: String(review.submission.assignmentID))
                                LabeledContent("Stage when answered", value: String(review.originalItem.srsStage))
                                LabeledContent("Meaning mistakes", value: String(review.submission.meaningWrongCount))
                                LabeledContent("Reading mistakes", value: String(review.submission.readingWrongCount))
                                if let timestamp = review.submission.createdAt {
                                    LabeledContent("Answered", value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted())
                                }
                                issue(review.issue, attempted: review.attempted)
                                if let remote = review.issue?.serverAssignment {
                                    LabeledContent("Last observed assignment", value: String(remote.id))
                                    LabeledContent("Last observed stage", value: String(remote.srsStage))
                                }
                                if !review.attempted, review.issue?.reason == .rejected {
                                    Button("Queue answer again") { run { try await store.queueRejectedReview(review) } }
                                        .disabled(isSyncing || performingAction)
                                }
                                wanikaniLink(review.subjectID)
                            }
                        }
                    }
                }
                if !work.materials.isEmpty {
                    Section("Notes and synonyms") {
                        ForEach(work.materials, id: \.revision) { saved in
                            DisclosureGroup(title(saved.material.subjectID)) {
                                Text("Your current edit").font(.headline)
                                material(saved.material)
                                if let attempted = saved.attemptedMaterial, attempted != saved.material {
                                    Text("Earlier edit sent to WaniKani").font(.headline)
                                    material(attempted)
                                }
                                issue(saved.issue, attempted: saved.attemptedRevision != nil)
                                if saved.attemptedRevision == nil, saved.issue?.reason == .rejected {
                                    Button("Queue edit again") { run { try await store.queueRejectedMaterial(saved) } }
                                        .disabled(isSyncing || performingAction)
                                }
                                wanikaniLink(saved.material.subjectID)
                            }
                        }
                    }
                }
            }
        }.formStyle(.grouped).navigationTitle("Saved work")
            .task(id: accountID) { await reload() }
            .onChange(of: isSyncing) { _, syncing in if !syncing { run {} } }
    }

    private func title(_ id: Int64) -> String {
        guard let subject = work?.subjects.first(where: { $0.id == id }) else { return "Subject \(id)" }
        return [subject.characters, subject.meaning].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    @ViewBuilder private func wanikaniLink(_ id: Int64) -> some View {
        if let url = work?.subjects.first(where: { $0.id == id })?.documentURL,
           url.scheme == "https", url.host == "www.wanikani.com" {
            Link("Check subject on WaniKani", destination: url)
        } else { Link("Open WaniKani", destination: URL(string: "https://www.wanikani.com/dashboard")!) }
    }
    @ViewBuilder private func material(_ value: StudyMaterial) -> some View {
        LabeledContent("Meaning note", value: value.meaningNote.isEmpty ? "None" : value.meaningNote).textSelection(.enabled)
        LabeledContent("Reading note", value: value.readingNote.isEmpty ? "None" : value.readingNote).textSelection(.enabled)
        LabeledContent("Synonyms", value: value.meaningSynonyms.isEmpty ? "None" : value.meaningSynonyms.joined(separator: ", ")).textSelection(.enabled)
    }
    @ViewBuilder private func issue(_ issue: StudyUploadIssue?, attempted: Bool) -> some View {
        let message: String = switch issue?.reason {
        case .uncertain: "WaniKani may have received this. Sending it again could repeat an answer or overwrite a newer note. It remains saved here."
        case .rejected: "WaniKani rejected this request. After checking the cause, you can queue it again and choose Sync saved work."
        case .assignmentChanged: "This assignment changed on WaniKani. The saved answer has not been applied to the new assignment."
        case .assignmentMissing: "This assignment is no longer available on WaniKani. The answer remains saved here."
        case nil: attempted ? "A previous attempt has no confirmed result. It will not be sent again automatically." : "Ready for the next sync."
        }
        Text(message).foregroundStyle(.secondary)
        if let status = issue?.httpStatus { LabeledContent("Server response", value: String(status)) }
        if let date = issue?.detectedAt { LabeledContent("Last checked", value: date.formatted()) }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !performingAction else { return }
        performingAction = true
        Task {
            defer { performingAction = false }
            error = nil
            do { try await action() } catch { self.error = error.localizedDescription }
            await reload()
        }
    }
    private func reload() async {
        do { work = try await store.savedWork(accountID: accountID) }
        catch { self.error = error.localizedDescription }
    }
}
