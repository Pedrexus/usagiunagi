import StudyCore
import StudyPersistence
import SwiftUI

/// Native offline reviews. The store commits each decision before the next question is shown.
public struct NativeReviewView: View {
  private let store: StudyStore
  private let accountID: String
  private let lessonSubjectIDs: [Int64]?
  private let finished: () -> Void
  private var isLesson: Bool { lessonSubjectIDs != nil }
  @State private var review: NativeReviewState?
  @State private var screen = ReviewScreenState()
  @State private var busy = false
  @State private var error: String?
  @State private var confirmEnd = false
  @State private var readyImage: String?
  @State private var voiceRequest: VoiceAnswerRequest?
  @State private var settings = false
  @State private var fullDetails = false
  @StoredReviewPreferences private var preferences
  @FocusState private var answerFocused: Bool

  public init(
    store: StudyStore, accountID: String, lessonSubjectIDs: [Int64]? = nil,
    finished: @escaping () -> Void = {}
  ) {
    self.store = store
    self.accountID = accountID
    self.lessonSubjectIDs = lessonSubjectIDs
    self.finished = finished
  }

  public var body: some View {
    VStack {
      if let review {
        if review.question != nil {
          HStack {
            Spacer()
            Button("Quick settings", systemImage: "slider.horizontal.3") { settings = true }
              .accessibilityIdentifier("review.settings")
            Button("End session", systemImage: "xmark") { confirmEnd = true }
          }.padding(.horizontal)
        }
        if review.question == nil {
          ContentUnavailableView(
            isLesson ? "Lesson quiz saved" : "Review session saved",
            systemImage: "checkmark.circle",
            description: Text(
              "\(review.saved.session.completedIDs.count) completed · \(review.saved.session.successRate)% accuracy. Completed answers stay on this Mac until you sync Saved work."
            ))
          Button("Finish session") {
            run {
              try await store.finishReviews(
                accountID: accountID, expectedRevision: review.saved.revision)
              self.review = nil
              finished()
            }
          }
        } else if let subject = review.subject {
          HStack {
            Text("Answers save automatically. Leave this page to pause.").font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Ask later") { change(.deferQuestion) }
            Button(review.saved.session.wrappingUp ? "Stop wrapping up" : "Wrap up") {
              change(review.saved.session.wrappingUp ? .stopWrapping : .wrapUp)
            }.disabled(!review.saved.session.canWrapUp && !review.saved.session.wrappingUp)
          }.padding(.horizontal)
          ReviewScreen(
            state: screen, action: act,
            question: {
              if let url = URL(string: subject.characterImageURL),
                !subject.characterImageURL.isEmpty
              {
                RadicalImageView(url: url) { available in
                  guard self.review?.subject?.characterImageURL == url.absoluteString else {
                    return
                  }
                  readyImage = available ? url.absoluteString : nil
                  screen.canAnswer = available
                }
              } else {
                Text("The radical image is missing. Refresh study content.").font(.caption)
              }
            }
          ) {
            TextField(screen.prompt, text: $screen.answer)
              .textFieldStyle(.roundedBorder).font(.title2).autocorrectionDisabled()
              .focused($answerFocused).onSubmit { act(.submit) }
              .accessibilityIdentifier("review.answer")
          } details: {
            NativeSubjectDetailsView(
              store: store, accountID: accountID, subjectID: subject.id,
              reviewQuestion: review.question?.kind, visibleQuestions: visibleQuestions)
          }
        } else {
          ContentUnavailableView(
            "Study content unavailable", systemImage: "photo",
            description: Text(
              "This question is missing catalog content. Your session remains saved. Refresh study content before continuing."
            ))
          Button("Ask this question later") { change(.deferQuestion) }
        }
      } else {
        ContentUnavailableView(
          isLesson ? "Lesson quiz" : "Offline reviews",
          systemImage: "rectangle.and.pencil.and.ellipsis",
          description: Text(
            isLesson
              ? "Quiz the lessons you selected. Each completed lesson stays saved on this device until you sync."
              : "Start with the reviews due in your saved account, or resume the session already saved on this Mac."
          ))
        Button(isLesson ? "Start or resume quiz" : "Start or resume reviews") { load() }
          .buttonStyle(.borderedProminent)
      }
      if busy { ProgressView("Saving") }
      if let error {
        Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
        Button("Reload saved session") { load() }
      }
    }
    .disabled(busy)
    .onChange(of: preferences) { _, _ in applyPreferences() }
    .sheet(isPresented: $settings, onDismiss: { answerFocused = screen.phase == .answering }) {
      ReviewSettingsPanel(preferences: preferences, changed: savePreferences, supportsAudio: false)
      {
        settings = false
      }
      .frame(minWidth: 380, minHeight: 460)
    }
    .confirmationDialog(
      isLesson ? "End lesson quiz?" : "End review session?", isPresented: $confirmEnd,
      titleVisibility: .visible
    ) {
      if let review {
        Button("End session", role: .destructive) {
          run {
            try await store.endReviews(
              accountID: accountID, expectedRevision: review.saved.revision)
            self.review = nil
            finished()
          }
        }
      }
    } message: {
      Text("Completed answers stay saved. Progress on unfinished subjects will be discarded.")
    }
    .sheet(item: $voiceRequest) { request in
      VoiceAnswerPanel(question: request.question) { text in
        voiceRequest = nil
        guard review?.question == request.question else { return }
        screen.answer = text
        submit(convertRomaji: false)
      } cancel: {
        voiceRequest = nil
      }
      .frame(minWidth: 420, minHeight: 440)
    }
    .task(id: accountID) { load() }
  }

  private func load() {
    run {
      let state =
        if let lessonSubjectIDs {
          try await store.openLessons(accountID: accountID, subjectIDs: lessonSubjectIDs)
        } else {
          try await store.openReviews(accountID: accountID)
        }
      present(state)
    }
  }
  private func run(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do { try await operation() } catch { self.error = error.localizedDescription }
    }
  }
  private func present(_ value: NativeReviewState) {
    if review?.question != value.question { fullDetails = false }
    review = value
    let session = value.saved.session
    screen.title = isLesson ? "Lesson quiz" : "Reviews"
    screen.question = value.subject?.japanese ?? ""
    screen.canAnswer =
      !screen.question.isEmpty
      || (readyImage != nil && readyImage == value.subject?.characterImageURL)
    screen.prompt = value.question?.kind == .reading ? "Reading" : "Meaning"
    screen.questionKind = value.question?.kind ?? .meaning
    screen.subjectColor =
      value.subject?.kind == .kanji
      ? StudyPalette.kanji
      : value.subject?.kind == .radical ? StudyPalette.radical : StudyPalette.vocabulary
    screen.level = value.subject.map { "Level \($0.level)" } ?? ""
    screen.completed = session.completedIDs.count
    screen.remaining = session.activeIDs.count + session.queuedIDs.count
    screen.accuracy = "\(session.successRate)%"
    screen.wrappingUp = session.wrappingUp
    screen.phase =
      session.currentDecision == .incorrect
      ? (preferences.revealAnswers ? .details : .incorrect) : .answering
    screen.answer = ""
    screen.feedback =
      session.currentDecision == .incorrect ? "Incorrect answer. Try again or reveal it." : ""
    applyPreferences()
    screen.success = nil
    if let success = value.success { screen.recordSuccess(success) }
    answerFocused = true
  }
  private func change(_ action: NativeReviewAction) {
    guard let review else { return }
    run {
      present(
        try await store.changeReview(
          action, accountID: accountID, expectedRevision: review.saved.revision))
    }
  }
  private func submit(convertRomaji: Bool = true) {
    guard screen.canAnswer, let review, let question = review.question else { return }
    let typed = screen.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else {
      if preferences.allowSkipping { change(.deferQuestion) }
      return
    }
    let exactMatch = preferences.exactMatch
    let answer =
      question.kind == .reading && convertRomaji ? KanaConverter.convert(typed).text : typed
    run {
      let result = try await store.answerReview(
        answer, question: question, accountID: accountID, expectedRevision: review.saved.revision,
        exactMatch: exactMatch)
      if result.state.question != question || result.grade == .incorrect {
        present(result.state)
      } else {
        self.review = result.state
        applyPreferences()
      }
      if result.state.question == question { screen.answer = result.normalized }
      switch result.grade {
      case .precise: break
      case .imprecise:
        if exactMatch {
          screen.feedback = "Use the exact meaning."
        }
      case .incorrect: break
      case .otherKanjiReading: screen.feedback = "Use the reading taught for this subject."
      case .mismatchingOkurigana: screen.feedback = "Check the kana following the kanji."
      case .containsInvalidCharacters: screen.feedback = "Enter this reading in kana."
      case .isReadingButWantMeaning:
        screen.feedback = "Enter the meaning. Your reading was correct."
      }
    }
  }
  private func act(_ action: ReviewScreenAction) {
    switch action {
    case .submit:
      if screen.phase == .details {
        change(.advance)
      } else if screen.phase == .incorrect {
        screen.phase = .details
      } else {
        submit()
      }
    case .reveal: screen.phase = .details
    case .showAll:
      fullDetails = true
      screen.canShowAll = false
    case .retry:
      screen.phase = .answering
      screen.answer = ""
      screen.feedback = ""
      answerFocused = true
    case .correct:
      if screen.canOverride { change(.overrideCorrect) }
    case .deferQuestion: change(.deferQuestion)
    case .voice:
      voiceRequest = review?.question.map { VoiceAnswerRequest(question: $0) }
    case .focus: answerFocused = true
    case .settings: settings = true
    default: break
    }
  }

  private func savePreferences(_ old: ReviewPreferences, _ new: ReviewPreferences) {
    do { try $preferences.applyChanges(from: old, to: new) } catch {
      self.error = error.localizedDescription
    }
  }
  private var visibleQuestions: Set<StudyQuestionKind> {
    if fullDetails || preferences.revealFullAnswer { return [.meaning, .reading] }
    guard let review, let question = review.question,
      let item = review.saved.session.items[question.itemID]
    else { return [] }
    var visible = Set<StudyQuestionKind>()
    if item.meaning.hasAttempts { visible.insert(.meaning) }
    if item.reading.hasAttempts { visible.insert(.reading) }
    return visible
  }
  private func applyPreferences() {
    let preferences = preferences
    screen.feedbackPreferences = preferences
    screen.questionSize = 72 * min(2.5, max(1, preferences.fontScale))
    screen.canSkip = preferences.allowSkipping
    screen.canOverride =
      !isLesson && preferences.allowCorrections
      && review?.saved.session.currentDecision == .incorrect
    let available: Set<StudyQuestionKind> =
      review?.subject?.readings.isEmpty == false ? [.meaning, .reading] : [.meaning]
    screen.canShowAll = !available.isSubset(of: visibleQuestions)
    let stage = review?.question.flatMap { review?.saved.session.items[$0.itemID]?.srsStage } ?? 0
    let name: String
    let dots: String
    switch stage {
    case 1...4:
      name = "Apprentice \(stage)"
      dots = String(repeating: "•", count: stage) + String(repeating: "◦", count: 4 - stage)
    case 5...6:
      name = "Guru \(stage - 4)"
      dots = String(repeating: "•", count: stage - 4) + String(repeating: "◦", count: 6 - stage)
    case 7:
      name = "Master"
      dots = "•"
    case 8:
      name = "Enlightened"
      dots = "•"
    case 9:
      name = "Burned"
      dots = "•"
    default:
      name = ""
      dots = ""
    }
    screen.stageAccessibility = name
    switch preferences.stageIndicator {
    case .none: screen.stage = ""
    case .name: screen.stage = name
    case .dots: screen.stage = dots
    }
  }
}
