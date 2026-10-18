import StudyCore
import StudyPersistence
import SwiftUI

/// Shared native recovery UI. The host owns credentials and synchronization lifetime.
public struct SavedWorkView: View {
  private let store: StudyStore
  private let accountID: String
  private let isSyncing: Bool
  private let synchronize: @MainActor () async throws -> Void
  private let compareMaterial:
    @MainActor (SavedStudyMaterial) async throws -> StudyMaterialComparison
  @State private var work: SavedStudyWork?
  @State private var error: String?
  @State private var performingAction = false
  @State private var comparison: StudyMaterialComparison?
  @State private var resolution: StudyMaterialResolution?

  public init(
    store: StudyStore, accountID: String, isSyncing: Bool,
    compareMaterial:
      @escaping @MainActor (SavedStudyMaterial) async throws -> StudyMaterialComparison,
    synchronize: @escaping @MainActor () async throws -> Void
  ) {
    self.store = store
    self.accountID = accountID
    self.isSyncing = isSyncing
    self.synchronize = synchronize
    self.compareMaterial = compareMaterial
  }

  public var body: some View {
    Form {
      Section {
        Text("Completed answers and note edits stay on this device until WaniKani accepts them.")
          .foregroundStyle(.secondary)
        if let work {
          LabeledContent("Answers waiting", value: String(work.reviews.count))
            .accessibilityElement(children: .ignore).accessibilityLabel("Answers waiting")
            .accessibilityValue(String(work.reviews.count)).accessibilityIdentifier(
              "savedWork.answerCount")
          LabeledContent("Note edits waiting", value: String(work.materials.count))
            .accessibilityElement(children: .ignore).accessibilityLabel("Note edits waiting")
            .accessibilityValue(String(work.materials.count)).accessibilityIdentifier(
              "savedWork.materialCount")
          if let retryAt = work.retryAt, retryAt > .now {
            Text(
              "WaniKani asked us to wait until \(retryAt.formatted(date: .omitted, time: .standard))."
            )
          }
          Button("Sync saved work", systemImage: "arrow.triangle.2.circlepath") {
            run { try await synchronize() }
          }.disabled(work.isEmpty || isSyncing || performingAction)
          Text(
            "Sync checks this account before sending eligible items. Uncertain or changed assignments remain saved for attention."
          )
          .font(.caption).foregroundStyle(.secondary)
          if work.isEmpty {
            Label("No saved work waiting", systemImage: "checkmark.circle")
          }
        } else if error == nil {
          ProgressView("Loading saved work")
        }
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
                LabeledContent(
                  "Meaning mistakes", value: String(review.submission.meaningWrongCount))
                LabeledContent(
                  "Reading mistakes", value: String(review.submission.readingWrongCount))
                if let timestamp = review.submission.createdAt {
                  LabeledContent(
                    "Answered",
                    value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted())
                }
                issue(review.issue, attempted: review.attempted)
                if let remote = review.issue?.serverAssignment {
                  LabeledContent("Last observed assignment", value: String(remote.id))
                  LabeledContent("Last observed stage", value: String(remote.srsStage))
                }
                if !review.attempted, review.issue?.reason == .rejected {
                  Button("Queue answer again") {
                    run { try await store.queueRejectedReview(review) }
                  }
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
                Button("Compare with WaniKani", systemImage: "arrow.left.arrow.right") {
                  checkMaterial(saved)
                }.disabled(isSyncing || performingAction)
                  .accessibilityIdentifier("savedWork.compare.\(saved.material.subjectID)")
                if saved.attemptedRevision == nil, saved.issue?.reason == .rejected {
                  Button("Queue edit again") {
                    run { try await store.queueRejectedMaterial(saved) }
                  }
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
      .sheet(
        item: $comparison, onDismiss: { resolution = nil }, content: { materialComparison($0) })
  }

  private func title(_ id: Int64) -> String {
    guard let subject = work?.subjects.first(where: { $0.id == id }) else { return "Subject \(id)" }
    return [subject.characters, subject.meaning].filter { !$0.isEmpty }.joined(separator: " · ")
  }
  @ViewBuilder private func wanikaniLink(_ id: Int64) -> some View {
    if let url = work?.subjects.first(where: { $0.id == id })?.documentURL,
      url.scheme == "https", url.host == "www.wanikani.com"
    {
      Link("Check subject on WaniKani", destination: url)
    } else {
      Link("Open WaniKani", destination: URL(string: "https://www.wanikani.com/dashboard")!)
    }
  }
  @ViewBuilder private func material(_ value: StudyMaterial) -> some View {
    materialField("Meaning note", value: value.meaningNote)
    materialField("Reading note", value: value.readingNote)
    materialField("Synonyms", value: value.meaningSynonyms.joined(separator: ", "))
  }
  private func materialField(_ name: String, value: String) -> some View {
    let text = value.isEmpty ? "None" : value
    return LabeledContent(name, value: text).textSelection(.enabled)
      .accessibilityElement(children: .ignore).accessibilityLabel(name).accessibilityValue(text)
  }
  @ViewBuilder private func issue(_ issue: StudyUploadIssue?, attempted: Bool) -> some View {
    let message: String =
      switch issue?.reason {
      case .uncertain:
        "WaniKani may have received this. Sending it again could repeat an answer or overwrite a newer note. It remains saved here."
      case .rejected:
        "WaniKani rejected this request. After checking the cause, you can queue it again and choose Sync saved work."
      case .assignmentChanged:
        "This assignment changed on WaniKani. The saved answer has not been applied to the new assignment."
      case .assignmentMissing:
        "This assignment is no longer available on WaniKani. The answer remains saved here."
      case .materialChanged:
        "This note changed on WaniKani after your comparison. Compare again before choosing which version to keep."
      case nil:
        attempted
          ? "A previous attempt has no confirmed result. It will not be sent again automatically."
          : "Ready for the next sync."
      }
    Text(message).foregroundStyle(.secondary)
    if let status = issue?.httpStatus { LabeledContent("Server response", value: String(status)) }
    if let date = issue?.detectedAt { LabeledContent("Last checked", value: date.formatted()) }
  }
  private func checkMaterial(_ saved: SavedStudyMaterial) {
    run {
      comparison = try await compareMaterial(saved)
      resolution = nil
    }
  }
  private func materialComparison(_ value: StudyMaterialComparison) -> some View {
    NavigationStack {
      Form {
        Section("Your saved edit") { material(value.saved.material) }
        if let attempted = value.saved.attemptedMaterial, attempted != value.saved.material {
          Section("Earlier edit sent to WaniKani") { material(attempted) }
        }
        Section("WaniKani version") {
          if let remote = value.remote {
            material(remote.value)
          } else {
            Text("No notes or synonyms are saved for this subject on WaniKani.")
          }
          Text("Checked \(value.checkedAt.formatted())").font(.caption).foregroundStyle(.secondary)
        }
        Section {
          Button("Keep my edit for next sync") { resolution = .keepLocal }
            .accessibilityIdentifier("savedWork.keepLocal")
          Button("Use WaniKani version", role: .destructive) { resolution = .useServer }
            .accessibilityIdentifier("savedWork.useServer")
          if let current = work?.materials.first(where: {
            $0.material.subjectID == value.saved.material.subjectID
          }) {
            Button("Check WaniKani again") { checkMaterial(current) }
          }
        } footer: {
          Text(
            "Keeping your edit does not send it. Sync checks the compared version again before sending. Changes made in another app during a sync can still conflict."
          )
        }
        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      }.formStyle(.grouped).disabled(performingAction || isSyncing)
        .navigationTitle("Resolve saved note")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { comparison = nil }.disabled(performingAction)
          }
        }
        .confirmationDialog(
          "Resolve this saved note?",
          isPresented: Binding(
            get: { resolution != nil }, set: { if !$0 { resolution = nil } }
          ), titleVisibility: .visible
        ) {
          if let choice = resolution {
            Button(
              choice == .keepLocal ? "Keep edit queued" : "Replace saved edit",
              role: choice == .useServer ? .destructive : nil
            ) {
              run {
                try await store.resolveMaterial(value, choice: choice)
                comparison = nil
              }
            }
          }
        } message: {
          Text(
            resolution == .keepLocal
              ? "Keep this device's current edit queued against the WaniKani version shown. Choose Sync saved work later to send it."
              : "Replace this device's pending note and synonyms with the WaniKani version shown here. This removes this pending edit."
          )
        }
    }.frame(idealWidth: 540, idealHeight: 640).interactiveDismissDisabled(performingAction)
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
    do { work = try await store.savedWork(accountID: accountID) } catch {
      self.error = error.localizedDescription
    }
  }
}
