import StudyCore
import StudyPersistence
import SwiftUI

/// Teaching and quizzes share the account's existing durable study session.
public struct NativeLessonView: View {
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudyAudioLibrary.self) private var audio
  @StoredReviewPreferences private var preferences
  @Environment(\.waniKaniPreferences) private var waniKaniPreferences
  private var waniKaniSources = StudyWaniKaniSources()
  private let store: StudyStore
  private let accountID: String
  private let automaticBatchSize: Int?
  private let finished: () -> Void
  @State private var initialBatchOpened = false
  @State private var items: [CatalogSubject] = []
  @State private var selectedIDs: Set<Int64> = []
  @State private var selection: Selection?
  @State private var pausedReview = false
  @State private var pausedLesson: Selection?
  @State private var loaded = false
  @State private var refreshID = UUID()
  @State private var error: String?
  private struct Selection: Identifiable {
    let id = UUID()
    let subjects: [CatalogSubject]
    var resumeQuiz = false
  }
  public init(
    store: StudyStore, accountID: String, automaticBatchSize: Int? = nil,
    finished: @escaping () -> Void = {}
  ) {
    self.store = store
    self.accountID = accountID
    self.automaticBatchSize = automaticBatchSize
    self.finished = finished
  }
  public var body: some View {
    Group {
      if let selection {
        LessonFlowView(
          subjects: selection.subjects,
          initialPage: selection.resumeQuiz ? selection.subjects.count : 0,
          backTitle: automaticBatchSize == nil ? "Choose lessons" : "Back",
          back: {
            if automaticBatchSize != nil {
              finished()
            } else {
              self.selection = nil
              refreshID = UUID()
            }
          },
          autoplay: { index in
            if waniKaniSources.audio, waniKaniPreferences?.lessonsAutoplayAudio == true {
              audio.play(
                subject: selection.subjects[index],
                interruptBackgroundAudio: preferences.interruptBackgroundAudio)
            }
          },
          playAudio: { index in
            audio.toggle(
              subject: selection.subjects[index],
              interruptBackgroundAudio: preferences.interruptBackgroundAudio)
          }
        ) { index in
          if index == selection.subjects.count {
            NativeReviewView(
              store: store, accountID: accountID,
              mode: .lessons(selection.subjects.map(\.id)),
              finished: {
                self.selection = nil
                finished()
                refreshID = UUID()
              })
          } else {
            NativeSubjectDetailsView(
              store: store, accountID: accountID,
              subjectID: selection.subjects[index].id)
          }
        }.id(selection.id)
      } else if let pausedLesson {
        VStack {
          Text("Finish or end your paused quiz before choosing different lessons.")
            .font(.callout).foregroundStyle(.secondary).padding()
          picker(pausedLesson.subjects, paused: pausedLesson)
        }
      } else if pausedReview {
        ContentUnavailableView(
          "A review session is paused", systemImage: "pause.circle",
          description: Text(
            "Open Reviews to finish or end that session before starting a lesson quiz. Your completed answers stay saved."
          ))
        Button("Check saved session") { refreshID = UUID() }
      } else if let error {
        ContentUnavailableView(
          "Lessons unavailable", systemImage: "books.vertical", description: Text(error))
        Button("Try again") { refreshID = UUID() }
      } else if loaded {
        picker(items)
      } else {
        ProgressView("Loading saved lessons")
      }
    }.navigationTitle("Lessons")
      .navigationBarBackButtonHidden(selection != nil)
      .task(
        id: LessonReadKey(
          accountID: accountID, preferences: lessonSettings.value, refreshID: refreshID)
      ) {
        if selection == nil { await load() }
      }
  }
  private func picker(_ items: [CatalogSubject], paused: Selection? = nil) -> some View {
    LessonPickerView(
      items: items,
      batchSize: paused?.subjects.count
        ?? lessonSettings.value.effectiveBatchSize(
          waniKani: waniKaniPreferences, followWaniKani: waniKaniSources.lessonBatch),
      selection: $selectedIDs
    ) { ids in
      if let paused {
        guard Set(ids) == Set(paused.subjects.map(\.id)) else {
          throw NativeReviewError.sessionInProgress(isLesson: true)
        }
        selection = Selection(subjects: paused.subjects)
        return
      }
      let available = try await store.availableLessons(
        accountID: accountID, lessonPreferences: lessonSettings.value)
      let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
      guard !ids.isEmpty, ids.allSatisfy({ byID[$0] != nil }) else {
        throw NativeReviewError.invalidLessonSelection
      }
      selection = Selection(subjects: ids.compactMap { byID[$0] })
    }
  }
  private struct LessonReadKey: Equatable {
    let accountID: String
    let preferences: StudyLessonPreferences
    let refreshID: UUID
  }
  private func load() async {
    error = nil
    loaded = false
    pausedReview = false
    pausedLesson = nil
    do {
      let saved = try await store.session(accountID: accountID)
      try Task.checkCancellation()
      if let saved {
        initialBatchOpened = true
        if saved.session.isPractice || saved.session.items.values.contains(where: { !$0.isLesson })
        {
          pausedReview = true
          return
        }
        let state = try await store.openLessons(accountID: accountID)
        let subjects = try state.saved.session.items.values.sorted { $0.id < $1.id }.map { item in
          guard let subject = state.subjects[item.subjectID] else {
            throw NativeReviewError.incompleteContent(item.subjectID)
          }
          return subject
        }
        try Task.checkCancellation()
        selectedIDs = Set(subjects.map(\.id))
        let resumed = Selection(subjects: subjects, resumeQuiz: true)
        if automaticBatchSize != nil { selection = resumed } else { pausedLesson = resumed }
      } else {
        let available = try await store.availableLessons(
          accountID: accountID, lessonPreferences: lessonSettings.value)
        try Task.checkCancellation()
        items = available
        selectedIDs.formIntersection(items.map(\.id))
        loaded = true
        if let automaticBatchSize, !initialBatchOpened, !items.isEmpty {
          initialBatchOpened = true
          selection = Selection(subjects: Array(available.prefix(max(1, automaticBatchSize))))
        }
      }
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
}
