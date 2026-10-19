import StudyCore
import StudyPersistence
import SwiftUI

/// Shared native recovery UI. The host owns credentials and synchronization lifetime.
public struct SavedWorkView: View {
  private let store: StudyStore
  private let accountID: String
  private let isSyncing: Bool
  private let synchronize: @MainActor () async throws -> Void
  private let compareSavedWork:
    @MainActor (StudyRecoveryRequest) async throws -> StudyRecoveryComparison
  @State private var work: SavedStudyWork?
  @State private var error: String?
  @State private var performingAction = false
  @State private var comparison: StudyRecoveryComparison?
  @State private var resolution: StudyMaterialResolution?
  @State private var confirmArchive = false

  public init(
    store: StudyStore, accountID: String, isSyncing: Bool,
    compareSavedWork:
      @escaping @MainActor (StudyRecoveryRequest) async throws -> StudyRecoveryComparison,
    synchronize: @escaping @MainActor () async throws -> Void
  ) {
    self.store = store
    self.accountID = accountID
    self.isSyncing = isSyncing
    self.synchronize = synchronize
    self.compareSavedWork = compareSavedWork
  }

  public var body: some View {
    Form {
      Section {
        Text("Completed answers and note edits stay on this device until WaniKani accepts them.")
          .foregroundStyle(.secondary)
        if let work {
          detailField("Answers waiting", value: String(work.reviews.count))
            .accessibilityIdentifier("savedWork.answerCount")
          detailField("Note edits waiting", value: String(work.materials.count))
            .accessibilityIdentifier("savedWork.materialCount")
          if work.requiresAssignmentRefresh {
            Label(
              "Refresh WaniKani to reload progress for archived answers.",
              systemImage: "arrow.clockwise"
            )
            .foregroundStyle(.secondary)
          }
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
                detailField("Type", value: review.submission.isLesson ? "Lesson" : "Review")
                detailField("Assignment", value: String(review.submission.assignmentID))
                detailField("Stage when answered", value: String(review.originalItem.srsStage))
                detailField(
                  "Meaning mistakes", value: String(review.submission.meaningWrongCount))
                detailField(
                  "Reading mistakes", value: String(review.submission.readingWrongCount))
                if let timestamp = review.submission.createdAt {
                  detailField(
                    "Answered",
                    value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted())
                }
                issue(review.issue, attempted: review.attempted)
                Button("Compare with WaniKani", systemImage: "arrow.left.arrow.right") {
                  run { comparison = try await compareSavedWork(.review(review)) }
                }.disabled(isSyncing || performingAction)
                  .accessibilityIdentifier("savedWork.compareAnswer.\(review.subjectID)")
                if let remote = review.issue?.serverAssignment {
                  detailField("Last observed assignment", value: String(remote.id))
                  detailField("Last observed stage", value: String(remote.srsStage))
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
      if let work, !work.archivedReviews.isEmpty {
        Section("Local answer archive") {
          Text(
            "These answers are kept on this device. They are not upload receipts and will not be sent again automatically."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(work.archivedReviews) { archived in
            DisclosureGroup(
              archived.subject.map {
                [$0.characters, $0.meaning].filter { !$0.isEmpty }.joined(separator: " · ")
              } ?? "Subject \(archived.saved.subjectID)"
            ) {
              detailField(
                "Type", value: archived.saved.submission.isLesson ? "Lesson" : "Review")
              detailField("Assignment", value: String(archived.saved.submission.assignmentID))
              detailField(
                "Meaning mistakes", value: String(archived.saved.submission.meaningWrongCount))
              detailField(
                "Reading mistakes", value: String(archived.saved.submission.readingWrongCount))
              detailField("Archived", value: archived.archivedAt.formatted())
              ShareLink(
                "Export saved answer", item: ArchivedReviewTransfer(value: archived),
                preview: SharePreview("Saved study answer"))
            }
          }
        }
      }
    }.formStyle(.grouped).navigationTitle("Saved work")
      .task(id: accountID) {
        for await _ in await store.changes() {
          guard !Task.isCancelled else { return }
          await reload()
        }
      }
      .onChange(of: isSyncing) { _, syncing in if !syncing { run {} } }
      .sheet(
        item: $comparison,
        onDismiss: {
          resolution = nil
          confirmArchive = false
        }, content: { recoverySheet($0) })
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
    detailField("Meaning note", value: value.meaningNote)
    detailField("Reading note", value: value.readingNote)
    detailField("Synonyms", value: value.meaningSynonyms.joined(separator: ", "))
  }
  private func detailField(_ name: String, value: String) -> some View {
    let text = value.isEmpty ? "None" : value
    return LabeledContent(name, value: text)
      .accessibilityIdentifier("savedWork.field.\(name)")
  }
  @ViewBuilder private func issue(_ issue: StudyUploadIssue?, attempted: Bool) -> some View {
    let message: String =
      switch issue?.reason {
      case .uncertain:
        "WaniKani may have received this. Sending it again could repeat an answer or overwrite a newer note. It remains saved here."
      case .rejected:
        "WaniKani rejected this request. After checking the cause, you can queue it again. It will sync automatically when online."
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
    if let status = issue?.httpStatus { detailField("Server response", value: String(status)) }
    if let date = issue?.detectedAt { detailField("Last checked", value: date.formatted()) }
  }
  private func checkMaterial(_ saved: SavedStudyMaterial) {
    run {
      comparison = try await compareSavedWork(.material(saved))
      resolution = nil
    }
  }
  @ViewBuilder private func recoverySheet(_ value: StudyRecoveryComparison) -> some View {
    switch value {
    case .material(let compared): materialComparison(compared)
    case .review(let compared): reviewComparison(compared)
    }
  }
  private func reviewComparison(_ value: StudyReviewComparison) -> some View {
    NavigationStack {
      Form {
        Section("Saved answer") {
          detailField("Type", value: value.saved.submission.isLesson ? "Lesson" : "Review")
          detailField("Assignment", value: String(value.saved.submission.assignmentID))
          detailField("Stage when answered", value: String(value.saved.originalItem.srsStage))
          detailField(
            "Meaning mistakes", value: String(value.saved.submission.meaningWrongCount))
          detailField(
            "Reading mistakes", value: String(value.saved.submission.readingWrongCount))
        }
        Section("WaniKani assignment") {
          if let remote = value.remote {
            detailField("Assignment", value: String(remote.id))
            detailField("Current stage", value: String(remote.srsStage))
            detailField("Lesson started", value: remote.startedAt == nil ? "No" : "Yes")
            if let date = remote.availableAt {
              detailField(
                "Next available", value: Date(timeIntervalSince1970: TimeInterval(date)).formatted()
              )
            }
            if remote.hidden == true { Text("This assignment is hidden on WaniKani.") }
          } else {
            Text("WaniKani returned no assignment for this subject.")
          }
          Text("Checked \(value.checkedAt.formatted())").font(.caption).foregroundStyle(.secondary)
        }
        Section {
          Text(
            "This read cannot confirm whether the saved answer was received. Keeping it pending does not send it again."
          )
          Button("Archive this answer and refresh later", systemImage: "archivebox") {
            confirmArchive = true
          }
          .accessibilityIdentifier("savedWork.archiveAnswer")
        } footer: {
          Text(
            "Archiving keeps the exact answer locally for inspection and export and removes it from the upload queue. Refresh WaniKani afterward to load current progress. This does not mark the old answer as successfully uploaded."
          )
        }
        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      }.formStyle(.grouped).disabled(performingAction || isSyncing)
        .navigationTitle("Resolve saved answer")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Keep pending") { comparison = nil }.disabled(performingAction)
          }
        }
        .confirmationDialog(
          "Archive this saved answer?", isPresented: $confirmArchive, titleVisibility: .visible
        ) {
          Button("Archive without sending") {
            run {
              try await store.archiveReview(value)
              comparison = nil
            }
          }
        } message: {
          Text(
            "The exact answer will stay in your local archive. It will leave the upload queue and this subject will require a refresh before reviewing again. WaniKani progress will not be changed."
          )
        }
    }.frame(idealWidth: 540, idealHeight: 620).interactiveDismissDisabled(performingAction)
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
              ? "Keep this device's current edit queued against the WaniKani version shown. It will sync automatically when online."
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
