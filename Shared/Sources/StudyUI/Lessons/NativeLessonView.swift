import StudyCore
import StudyPersistence
import SwiftUI

/// Teaching and quizzes share the account's existing durable study session.
public struct NativeLessonView: View {
  private let store: StudyStore
  private let accountID: String
  private let automaticBatchSize: Int?
  private let finished: () -> Void
  @State private var initialBatchOpened = false
  @State private var items: [StudySubject] = []
  @State private var selection: Selection?
  @State private var pausedReview = false
  @State private var pausedLesson: Selection?
  @State private var loaded = false
  @State private var error: String?
  private struct Selection: Identifiable {
    let id = UUID()
    let subjects: [StudySubject]
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
          back: {
            self.selection = nil
            Task { await load() }
          }
        ) { index in
          if index == selection.subjects.count {
            NativeReviewView(
              store: store, accountID: accountID,
              mode: .lessons(selection.subjects.map(\.id)),
              finished: {
                self.selection = nil
                finished()
                Task { await load() }
              })
          } else {
            NativeSubjectDetailsView(
              store: store, accountID: accountID,
              subjectID: selection.subjects[index].id)
          }
        }.id(selection.id)
      } else if let pausedLesson {
        ContentUnavailableView(
          "Lesson quiz paused", systemImage: "pause.circle",
          description: Text(
            "Your answers are saved. Resume this quiz before choosing different lessons."))
        Button("Resume lesson quiz") { selection = pausedLesson }.buttonStyle(.borderedProminent)
      } else if pausedReview {
        ContentUnavailableView(
          "A review session is paused", systemImage: "pause.circle",
          description: Text(
            "Open Reviews to finish or end that session before starting a lesson quiz. Your completed answers stay saved."
          ))
        Button("Check saved session") { Task { await load() } }
      } else if let error {
        ContentUnavailableView(
          "Lessons unavailable", systemImage: "books.vertical", description: Text(error))
        Button("Try again") { Task { await load() } }
      } else if loaded {
        LessonPickerView(items: items) { ids in
          let available = try await store.availableLessons(accountID: accountID)
          let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0.summary) })
          guard !ids.isEmpty, ids.allSatisfy({ byID[$0] != nil }) else {
            throw NativeReviewError.invalidLessonSelection
          }
          selection = Selection(subjects: ids.compactMap { byID[$0] })
        }
      } else {
        ProgressView("Loading saved lessons")
      }
    }.task(id: accountID) { if selection == nil { await load() } }
  }
  private func load() async {
    error = nil
    loaded = false
    pausedReview = false
    pausedLesson = nil
    do {
      if let saved = try await store.session(accountID: accountID) {
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
          return subject.summary
        }
        try Task.checkCancellation()
        let resumed = Selection(subjects: subjects, resumeQuiz: true)
        if automaticBatchSize != nil { selection = resumed } else { pausedLesson = resumed }
      } else {
        let available = try await store.availableLessons(accountID: accountID)
        try Task.checkCancellation()
        items = available.map(\.summary)
        loaded = true
        if let automaticBatchSize, !initialBatchOpened, !items.isEmpty {
          initialBatchOpened = true
          selection = Selection(subjects: Array(items.prefix(max(1, automaticBatchSize))))
        }
      }
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
}
