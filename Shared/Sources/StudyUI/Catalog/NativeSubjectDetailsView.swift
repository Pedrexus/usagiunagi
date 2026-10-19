import StudyCore
import StudyPersistence
import SwiftUI

public struct NativeSubjectDetailsView: View {
  private let store: StudyStore
  private let accountID: String
  private let subjectID: Int64
  private let reviewQuestion: StudyQuestionKind?
  private let visibleQuestions: Set<StudyQuestionKind>
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudySubjectSettings.self) private var subjectSettings
  @State private var savingExclusion = false
  @Environment(StudyAudioLibrary.self) private var audio
  @StoredReviewPreferences private var preferences
  @State private var details: StudySubjectDetails?
  @State private var error: String?
  @State private var editing = false
  @State private var refreshID = UUID()
  @State private var relatedSubject: Int64?

  public init(
    store: StudyStore, accountID: String, subjectID: Int64,
    reviewQuestion: StudyQuestionKind? = nil,
    visibleQuestions: Set<StudyQuestionKind> = [.meaning, .reading]
  ) {
    self.store = store
    self.accountID = accountID
    self.subjectID = subjectID
    self.reviewQuestion = reviewQuestion
    self.visibleQuestions = visibleQuestions
  }
  private func setExcluded(_ excluded: Bool) async {
    guard !savingExclusion else { return }
    savingExclusion = true
    error = nil
    defer { savingExclusion = false }
    do {
      details = try await store.setSubjectExcluded(
        subjectID: subjectID, accountID: accountID, excluded: excluded)
    } catch { self.error = error.localizedDescription }
  }
  public var body: some View {
    Group {
      if let details {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if reviewQuestion == nil { SubjectDetailsHeader(subject: details.subject) }
            SubjectDetailsContent(
              subject: details.subject, material: details.material, assignment: details.assignment,
              components: details.components, combinations: details.combinations,
              similar: subjectSettings.value.visibleSimilar(
                details.similar, currentLevel: details.currentLevel),
              preferences: subjectSettings.value,
              visibleQuestions: visibleQuestions, reviewQuestion: reviewQuestion,
              edit: { editing = true }, openSubject: { relatedSubject = $0 },
              playAudio: details.subject.audio.isEmpty
                ? nil
                : {
                  audio.toggle(
                    subject: details.subject,
                    interruptBackgroundAudio: preferences.interruptBackgroundAudio)
                },
              audioState: audio.state(for: subjectID), audioError: audio.error(for: subjectID)
            ).padding(.horizontal)
            if reviewQuestion == nil, details.subject.kind == .vocabulary,
              lessonSettings.value.allowVocabularyExclusion
            {
              SubjectExclusionControl(
                excluded: Binding(
                  get: { details.material?.isExcluded == true },
                  set: { value in Task { await setExcluded(value) } })
              )
              .disabled(savingExclusion).padding(.horizontal)
              if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                  .font(.callout).padding(.horizontal).accessibilityIdentifier(
                    "subject.exclusionError")
              }
            }
            if details.savedMaterial?.pending == true {
              Text("Changes saved on this device. Sync them from Saved work.").font(.caption)
                .foregroundStyle(.secondary).padding(.horizontal)
            }
            if details.unavailableRelatedCount > 0 {
              Text("Some related subjects are outside your saved catalog or content access.").font(
                .caption
              ).foregroundStyle(.secondary).padding(.horizontal)
            }
          }.padding(.bottom)
        }
      } else if let error {
        ContentUnavailableView(
          "Subject unavailable", systemImage: "book.closed", description: Text(error))
      } else {
        ProgressView("Loading saved subject")
      }
    }
    .sheet(isPresented: $editing, onDismiss: { refreshID = UUID() }) {
      if let details {
        StudyMaterialEditor(
          subject: details.subject,
          initial: StudyMaterialEdit(
            material: details.material ?? StudyMaterial(subjectID: subjectID),
            version: details.savedMaterial?.revision),
          visibleQuestions: SubjectDetailVisibility(visibleQuestions).editableQuestions,
          saveMessage: "Save keeps changes on this device. Send them to WaniKani from Saved work."
        ) { material, version in
          do {
            try await store.saveSubjectMaterial(
              material, accountID: accountID, expectedRevision: version)
          } catch StudyStoreError.staleMaterial {
            let latest = try await store.subjectDetails(subjectID: subjectID, accountID: accountID)
            throw StudyMaterialEditConflict(
              current: StudyMaterialEdit(
                material: latest.material ?? StudyMaterial(subjectID: subjectID),
                version: latest.savedMaterial?.revision))
          }
        }
      }
    }
    .task(id: [accountID, String(subjectID), refreshID.uuidString]) {
      details = nil
      error = nil
      do {
        let value = try await store.subjectDetails(subjectID: subjectID, accountID: accountID)
        try Task.checkCancellation()
        details = value
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    .navigationDestination(item: $relatedSubject) { id in
      NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id).navigationTitle(
        "Related subject")
    }
  }
}
