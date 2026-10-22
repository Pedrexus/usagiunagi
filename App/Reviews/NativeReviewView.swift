import StudyCore
import StudyPersistence
import SwiftUI

public enum NativeStudyMode: Hashable, Sendable {
  case reviews
  case lessons([Int64])
  case practice(StudyPracticeScope)
}

/// Native offline reviews. The store commits each decision before the next question is shown.
public struct NativeReviewView: View {
  private let store: StudyStore
  private let accountID: String
  private let mode: NativeStudyMode
  private var isPractice: Bool { if case .practice = mode { true } else { false } }
  @Binding private var wrapUpRequested: Bool
  private let finished: () -> Void
  private var isLesson: Bool { if case .lessons = mode { true } else { false } }
  @State private var review: NativeReviewState?
  @State private var screen = ReviewScreenState()
  @State private var busy = false
  @State private var ended = false
  @State private var error: String?
  @State private var summarySubjectID: Int64?
  @State private var readyImage: String?
  @State private var voiceAttempt = UUID()
  @Environment(\.scenePhase) private var scenePhase
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudyAudioLibrary.self) private var audio
  @Environment(\.studyVoiceCapture) private var voiceCapture
  @Environment(StudyFontLibrary.self) private var fonts
  @State private var settings = false
  @State private var addingSynonym = false
  @State private var synonym = ""
  @State private var fontSubjectID: Int64?
  @State private var customFont = ""
  @State private var fullDetails = false
  @AppStorage("native.autoSwitchKeyboard") private var automaticJapanese = false
  @Environment(StudySubjectSettings.self) private var subjectSettings
  @StoredReviewPreferences private var preferences
  @Environment(\.waniKaniPreferences) private var waniKaniPreferences
  private var waniKaniSources = StudyWaniKaniSources()
  // Only transient UI state. Submitted answers remain in the revision-checked store/outbox.
  @SceneStorage("review.draft.identity") private var draftIdentity = ""
  @SceneStorage("review.draft.answer") private var draftAnswer = ""
  @SceneStorage("review.draft.feedback") private var draftFeedback = ""
  @SceneStorage("review.draft.phase") private var draftPhase = ReviewScreenState.Phase.answering
  @State private var answerFocused = false

  public init(
    store: StudyStore, accountID: String, mode: NativeStudyMode = .reviews,
    wrapUpRequested: Binding<Bool> = .constant(false), finished: @escaping () -> Void = {}
  ) {
    self.store = store
    self.accountID = accountID
    self.mode = mode
    _wrapUpRequested = wrapUpRequested
    self.finished = finished
  }

  public var body: some View {
    VStack {
      AudioPlaybackNotice(library: audio)
      if audio.state != .idle {
        Button(
          audio.state == .loading ? "Cancel loading pronunciation" : "Stop pronunciation",
          systemImage: "stop.circle"
        ) { audio.stop() }.accessibilityIdentifier("review.stopAudio")
      }
      if let review {
        if ended || review.question == nil {
          SessionSummaryView(
            summary: review.summary(showOldMeanings: subjectSettings.value.showDeprecatedMnemonic),
            title: isPractice
              ? "Practice complete" : isLesson ? "Lesson quiz saved" : "Review session saved",
            message: isPractice
              ? "Practice answers do not change WaniKani progress or create review uploads."
              : "Completed answers are saved on this device and sync automatically when online.",
            imageURL: { id in
              guard let item = review.saved.session.items[id],
                let path = review.subjects[item.subjectID]?.characterImageURL, !path.isEmpty
              else { return nil }
              return URL(string: path)
            }
          ) { id in summarySubjectID = review.saved.session.items[id]?.subjectID }
          .navigationTitle(
            isPractice ? "Practice summary" : isLesson ? "Lesson summary" : "Review summary"
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") {
                run {
                  if !ended {
                    try await store.finishReviews(
                      accountID: accountID, expectedRevision: review.saved.revision)
                  }
                  self.review = nil
                  finished()
                }
              }.keyboardShortcut(.defaultAction).accessibilityIdentifier("review.finish")
            }
          }
        } else if let subject = review.subject {
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
            if screen.voiceEnabled, screen.phase == .answering, let question = review.question {
              if !settings && !busy && error == nil && screen.canAnswer {
                VoiceAnswerControls(
                  model: VoiceReviewController(question: question, capture: voiceCapture()),
                  automaticallySubmit: true,
                  startDelay: !screen.feedback.isEmpty
                    ? .seconds(3) : screen.success == nil ? .zero : .milliseconds(650),
                  submit: { text in
                    guard self.review?.question == question, screen.voiceEnabled, !busy else {
                      return
                    }
                    screen.answer = text
                    submit(convertRomaji: false)
                  }, cancel: { screen.voiceEnabled = false }
                ).id(question).id(voiceAttempt)
              }
            } else {
              StudyAnswerInput(
                prompt: screen.prompt, text: $screen.answer,
                focused: $answerFocused,
                reading: screen.questionKind == .reading, automaticJapanese: automaticJapanese,
                editable: screen.phase == .answering,
                alphabet: subjectSettings.value.useKatakanaForOnyomi
                  && subject.readings.first(where: \.isPrimary)?.kind == .onyomi
                  ? .katakana : .hiragana,
                submitted: { act(.submit) }, retried: { act(.retry) }
              ).frame(minHeight: 44)
            }
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
      } else if error == nil {
        ProgressView("Opening study session")
      }
      if busy && review != nil { ProgressView("Saving") }
      if let error {
        Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
        Button("Reload saved session") { load() }
      }
    }
    .disabled(busy)
    .onDisappear {
      rememberDraft()
      audio.stop()
    }
    .onChange(of: screen.answer) { _, _ in rememberDraft() }
    .onChange(of: screen.phase) { _, _ in rememberDraft() }
    .onChange(of: screen.feedback) { _, _ in rememberDraft() }
    .onChange(of: screen.voiceEnabled) { _, enabled in
      answerFocused = !enabled && screen.phase == .answering && !screen.isAnki
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { screen.voiceEnabled = false }
    }
    .onChange(of: wrapUpRequested, initial: true) { _, _ in applyWrapUpRequest() }
    .onChange(of: busy) { _, _ in applyWrapUpRequest() }
    .onChange(of: preferences) { _, _ in applyPreferences() }
    .onChange(of: waniKaniPreferences) { _, _ in applyPreferences() }
    .onChange(of: waniKaniSources.srsFeedback) { _, _ in applyPreferences() }
    .onChange(of: lessonSettings.value.allowVocabularyExclusion) { _, _ in applyPreferences() }
    .onChange(of: fonts.selectedFiles) { _, _ in chooseFont(newSubject: false) }
    .onChange(of: screen.phase) { _, _ in applyFont() }
    .sheet(
      isPresented: $settings,
      onDismiss: {
        answerFocused = screen.phase != .details && !screen.isAnki && !screen.voiceEnabled
      }
    ) {
      ReviewSettingsSheet(
        preferences: preferences, changed: savePreferences, fonts: fonts, audio: audio
      ) {
        settings = false
      }
    }

    .alert("Add synonym", isPresented: $addingSynonym) {
      TextField("Meaning", text: $synonym).autocorrectionDisabled()
      Button("Add and mark correct") { change(.addSynonym(synonym)) }
        .disabled(synonym.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Accept this meaning for future reviews.")
    }
    .navigationDestination(item: $summarySubjectID) { id in
      NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id)
        .navigationTitle("Subject")
    }
    .onChange(of: summarySubjectID) { previous, current in
      guard previous != nil, current == nil, !ended, review?.question != nil,
        screen.phase != .details, !screen.isAnki, !screen.voiceEnabled
      else { return }
      answerFocused = true
    }
    .task(id: voiceCorrectionRevision) {
      guard let revision = voiceCorrectionRevision else { return }
      do { try await Task.sleep(for: .seconds(3)) } catch { return }
      guard voiceCorrectionRevision == revision, scenePhase == .active else { return }
      change(.advance)
    }
    .task(id: accountID) { if review == nil { load() } }
  }

  private var voiceCorrectionRevision: UUID? {
    screen.voiceEnabled && !busy && !settings && error == nil
      && screen.phase != .answering
      && review?.saved.session.currentDecision == .incorrect ? review?.saved.revision : nil
  }

  private func load() {
    run {
      let state: NativeReviewState
      switch mode {
      case .reviews:
        state = try await store.openReviews(
          accountID: accountID, options: preferences.sessionOptions,
          lessonPreferences: lessonSettings.value,
          policy: preferences.reviewPolicy(
            waniKani: waniKaniPreferences, followWaniKani: waniKaniSources.reviewOrder))
      case .lessons(let ids):
        state = try await store.openLessons(
          accountID: accountID, subjectIDs: ids, options: preferences.sessionOptions,
          lessonPreferences: lessonSettings.value)
      case .practice(let scope):
        state = try await store.openPractice(
          accountID: accountID, scope: scope, options: preferences.sessionOptions,
          lessonPreferences: lessonSettings.value, policy: preferences.policy)
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
      do { try await operation() } catch {
        screen.voiceEnabled = false
        self.error = error.localizedDescription
      }
    }
  }
  private func present(_ value: NativeReviewState) {
    if review?.question != value.question { fullDetails = false }
    let previous = review
    let restoringDraft =
      previous == nil && value.question != nil && !value.isAnki
      && draftIdentity == draftKey(value)
    review = value
    if !screen.voiceEnabled, value.success != nil, let previous, let subject = previous.subject,
      !subject.audio.isEmpty,
      preferences.autoplay(
        in: isLesson ? .lessons : isPractice ? .extraStudy : .reviews,
        waniKani: waniKaniPreferences,
        followWaniKani: waniKaniSources.audio
      ),
      previous.question?.kind == .reading || subject.readings.isEmpty || previous.combinesAnki
    {
      audio.play(subject: subject, interruptBackgroundAudio: preferences.interruptBackgroundAudio)
    }
    let newSubject = fontSubjectID != value.subject?.id
    fontSubjectID = value.subject?.id
    let session = value.saved.session
    screen.title =
      review?.saved.session.practiceScope?.title ?? (isLesson ? "Lesson quiz" : "Reviews")
    screen.question = value.subject?.japanese ?? ""
    screen.canPlayAudio = !(value.subject?.audio.isEmpty ?? true)
    screen.canAnswer =
      !screen.question.isEmpty
      || (readyImage != nil && readyImage == value.subject?.characterImageURL)
    screen.prompt =
      value.combinesAnki
      ? (session.options.meaningFirst ? "Meaning + Reading" : "Reading + Meaning")
      : value.question?.kind == .reading ? "Reading" : "Meaning"
    screen.questionKind = value.question?.kind ?? .meaning
    screen.subjectType = value.subject?.kind.rawValue.capitalized ?? ""
    screen.subjectColor =
      value.subject?.kind == .kanji
      ? StudyPalette.kanji
      : value.subject?.kind == .radical ? StudyPalette.radical : StudyPalette.vocabulary
    screen.level = value.subject.map { "Level \($0.level)" } ?? ""
    screen.previous =
      session.completedIDs.last.flatMap { id in
        session.items[id].flatMap { value.subjects[$0.subjectID] }.map {
          $0.japanese.isEmpty ? "Radical" : $0.japanese
        }
      } ?? ""
    screen.completed = session.completedIDs.count
    screen.remaining = session.activeIDs.count + session.queuedIDs.count
    screen.accuracy = "\(session.successRate)%"
    screen.wrappingUp = session.wrappingUp
    screen.hasMenu = true
    screen.endTitle =
      isPractice ? "End practice" : isLesson ? "End lesson quiz" : "End review session"
    screen.canWrapUp = session.canWrapUp || session.wrappingUp
    screen.activeCount = session.activeIDs.count
    screen.phase =
      session.currentDecision == .incorrect
      ? (value.isAnki || preferences.revealAnswers ? .details : .incorrect) : .answering
    screen.answer = restoringDraft ? draftAnswer : ""
    screen.answerHint = nil
    screen.feedback =
      session.currentDecision == .incorrect ? "Incorrect answer. Try again or reveal it." : ""
    if restoringDraft {
      screen.phase = draftPhase
      screen.feedback = draftFeedback
    }
    applyPreferences()
    rememberDraft()
    screen.success = nil
    if let success = value.success { screen.recordSuccess(success) }
    chooseFont(newSubject: newSubject)
    answerFocused = !value.isAnki && !screen.voiceEnabled
  }
  private func draftKey(_ state: NativeReviewState) -> String {
    accountID + ":" + state.saved.revision.uuidString
  }
  private func rememberDraft() {
    guard let review else { return }
    guard review.question != nil, !review.isAnki else {
      draftIdentity = ""
      draftAnswer = ""
      draftFeedback = ""
      draftPhase = .answering
      return
    }
    draftIdentity = draftKey(review)
    draftAnswer = screen.answer
    draftFeedback = screen.feedback
    draftPhase = screen.phase
  }
  private func applyWrapUpRequest() {
    guard wrapUpRequested, !busy, let review else { return }
    wrapUpRequested = false
    if review.question != nil { change(.wrapUp) }
  }
  private func change(_ action: NativeReviewAction) {
    guard let review else { return }
    run {
      let value = try await store.changeReview(
        action, accountID: accountID, expectedRevision: review.saved.revision)
      if case .exclude = action, let subject = review.subject, audio.state(for: subject.id) != .idle
      {
        audio.stop()
      }
      present(value)
    }
  }
  private func revealAnki() {
    guard let review, let question = review.question else { return }
    run {
      present(
        try await store.revealAnki(
          question: question, accountID: accountID,
          expectedRevision: review.saved.revision))
    }
  }
  private func assessAnki(_ correct: Bool) {
    guard screen.phase == .details, let review, let question = review.question else { return }
    run {
      present(
        try await store.assessAnki(
          correct: correct, question: question, accountID: accountID,
          expectedRevision: review.saved.revision))
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
      screen.showAnswerHint(result.grade, exactMatch: exactMatch)
      if screen.voiceEnabled { voiceAttempt = UUID() }
      if screen.voiceEnabled, result.grade == .incorrect, let subject = review.subject {
        let expected =
          question.kind == .reading
          ? subject.readings.filter(\.isPrimary).map(\.text)
          : subject.meanings.filter { $0.role != .blacklist }.map(\.text)
        screen.feedback = "Incorrect. Answer: " + expected.joined(separator: ", ")
      }
    }
  }
  private func act(_ action: ReviewScreenAction) {
    switch action {
    case .submit:
      if screen.isAnki {
        if screen.phase == .answering { revealAnki() } else { screen.showAssessment = true }
      } else if screen.phase == .details {
        change(.advance)
      } else if screen.phase == .incorrect {
        change(.advance)
      } else {
        submit()
      }
    case .reveal:
      screen.voiceEnabled = false
      screen.phase = .details
    case .showAll:
      fullDetails = true
      screen.canShowAll = false
    case .retry:
      screen.phase = .answering
      screen.answer = ""
      screen.feedback = ""
      answerFocused = !screen.voiceEnabled
    case .correct:
      if screen.isAnki { assessAnki(true) } else if screen.canOverride { change(.overrideCorrect) }
    case .incorrect:
      if screen.isAnki { assessAnki(false) } else if screen.phase == .details { change(.advance) }
    case .synonym:
      guard screen.phase == .details, screen.canAddSynonym, screen.canOverride || screen.isAnki
      else { return }
      synonym = screen.answer
      addingSynonym = true
    case .previous:
      screen.voiceEnabled = false
      if let session = review?.saved.session, let id = session.completedIDs.last {
        summarySubjectID = session.items[id]?.subjectID
      }
    case .deferQuestion: change(.deferQuestion)
    case .exclude:
      guard screen.phase == .details, screen.canExclude, screen.canOverride || screen.isAnki else {
        return
      }
      change(.exclude)
    case .voice:
      answerFocused = false
      audio.stop()
      screen.voiceEnabled.toggle()
    case .focus: answerFocused = true
    case .settings:
      answerFocused = false
      settings = true
    case .wrap: change(.wrapUp)
    case .stopWrapping: change(.stopWrapping)
    case .end:
      guard let review else { return }
      run {
        try await store.endReviews(accountID: accountID, expectedRevision: review.saved.revision)
        answerFocused = false
        screen.voiceEnabled = false
        draftIdentity = ""
        if review.saved.session.completedIDs.isEmpty {
          self.review = nil
          finished()
        } else {
          ended = true
        }
      }
    case .playAudio:
      if let subject = review?.subject {
        audio.toggle(
          subject: subject, interruptBackgroundAudio: preferences.interruptBackgroundAudio)
      }
    case .toggleFont:
      if screen.canChangeFont {
        screen.questionFont = screen.questionFont.isEmpty ? customFont : ""
      }
    case .nextFont: cycleFont(1)
    case .previousFont: cycleFont(-1)
    }
  }

  private func chooseFont(newSubject: Bool) {
    let available = isLesson ? [] : fonts.fontNames(for: screen.question)
    if newSubject || !available.contains(customFont) {
      customFont = available.randomElement() ?? ""
    }
    screen.canChangeFont = !available.isEmpty
    applyFont()
  }
  private func applyFont() { screen.questionFont = screen.phase == .details ? "" : customFont }
  private func cycleFont(_ offset: Int) {
    guard screen.canChangeFont else { return }
    let available = fonts.fontNames(for: screen.question)
    guard !available.isEmpty else { return }
    let index = available.firstIndex(of: customFont) ?? 0
    customFont = available[(index + offset + available.count) % available.count]
    applyFont()
  }
  private func savePreferences(_ old: ReviewPreferences, _ new: ReviewPreferences) {
    do { try $preferences.applyChanges(from: old, to: new) } catch {
      self.error = error.localizedDescription
    }
  }
  private var visibleQuestions: Set<StudyQuestionKind> {
    if fullDetails || preferences.revealFullAnswer || review?.combinesAnki == true {
      return [.meaning, .reading]
    }
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
    screen.completedSrsChanges =
      !isLesson && !isPractice && waniKaniSources.srsFeedback
      ? waniKaniPreferences?.reviewsDisplaySrsIndicator : nil
    screen.isAnki = review?.isAnki == true
    if screen.isAnki { screen.voiceEnabled = false }
    screen.feedbackPreferences = preferences
    screen.questionSize = 72 * min(2.5, max(1, preferences.fontScale))
    screen.canSkip = preferences.allowSkipping
    screen.canExclude =
      review?.subject?.kind == .vocabulary && lessonSettings.value.allowVocabularyExclusion
    screen.canOverride =
      !isLesson && preferences.allowCorrections
      && review?.saved.session.currentDecision == .incorrect
    let available: Set<StudyQuestionKind> =
      review?.subject?.readings.isEmpty == false ? [.meaning, .reading] : [.meaning]
    screen.canAddSynonym = review?.question?.kind == .meaning
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
