import StudyCore
import SwiftUI

/// The shared practice destination uses the same saved study options on every platform.
struct KatakanaPracticeMenu: View {
  let start: () -> Void
  var body: some View {
    Form {
      Section {
        Button("Katakana characters", systemImage: "character.ja", action: start)
          .accessibilityIdentifier("practice.katakana")
        Text("ア · シ · ツ · ソ · ン").font(.title2)
      } footer: {
        Text(
          "Practice the reading of katakana characters. Practice does not change your WaniKani progress."
        )
      }
    }
    .formStyle(.grouped)
  }
}

struct KatakanaPracticeSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(StudyFontLibrary.self) private var fonts
  @Environment(\.studyVoiceCapture) private var voiceCapture
  @AppStorage("native.autoSwitchKeyboard") private var automaticJapanese = false
  @StoredReviewPreferences private var preferences
  @State private var practice: KatakanaPractice?
  @State private var screen = ReviewScreenState()
  @State private var error: String?
  @State private var ended = false
  @State private var settings = false
  @State private var summarySubject: Int?
  @State private var customFont = ""
  @State private var voiceRequest: VoiceAnswerRequest?
  @State private var focused = false

  var body: some View {
    VStack {
      if let practice {
        if ended || practice.question == nil {
          SessionSummaryView(
            summary: practice.summary,
            message: "Practice answers do not change WaniKani progress or create review uploads."
          ) { summarySubject = $0 }
          .navigationTitle("Review Summary")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("review.finish")
            }
          }
        } else {
          Text("Practice only · WaniKani progress is unchanged").font(.caption)
            .foregroundStyle(.secondary).padding(.top, 8)
          ReviewScreen(state: screen, action: act) {
            StudyAnswerInput(
              prompt: "Reading", text: $screen.answer,
              focused: $focused, reading: true,
              automaticJapanese: automaticJapanese, editable: screen.phase == .answering,
              alphabet: .hiragana,
              submitted: { act(.submit) }, retried: { act(.retry) }
            ).frame(minHeight: 44)
          } details: {
            reading(practice.subject)
          }
        }
      }
      if let error { Text(error).foregroundStyle(.red).padding() }
    }
    .interactiveDismissDisabled(!ended && practice?.question != nil)
    .navigationDestination(item: $summarySubject) { id in
      VStack(spacing: 16) {
        Text(KatakanaPractice.characters[id]).font(.largeTitle)
        reading(KatakanaPractice.subject(at: id))
      }
      .padding().navigationTitle("Katakana reading")
    }
    .sheet(
      isPresented: $settings,
      onDismiss: { focused = screen.phase != .details && !screen.isAnki }
    ) {
      ReviewSettingsSheet(preferences: preferences, changed: savePreferences, fonts: fonts) {
        settings = false
      }
    }
    .sheet(
      item: $voiceRequest,
      onDismiss: { focused = screen.phase != .details && !screen.isAnki }
    ) { request in
      VoiceAnswerPanel(
        model: VoiceReviewController(question: request.question, capture: voiceCapture())
      ) { answer in
        voiceRequest = nil
        guard practice?.question == request.question else { return }
        screen.answer = answer
        submit(convertRomaji: false)
      } cancel: {
        voiceRequest = nil
      }
      .presentationSizing(.form)
    }
    .task {
      guard practice == nil else { return }
      perform {
        practice = try KatakanaPractice(options: preferences.sessionOptions)
        present()
      }
    }
    .onChange(of: preferences) { _, _ in applyPreferences() }
    .onChange(of: fonts.selectedFiles) { _, _ in chooseFont() }
    .onChange(of: screen.phase) { _, phase in
      screen.questionFont = phase == .details ? "" : customFont
    }
  }

  private func reading(_ subject: GradingSubject?) -> some View {
    VStack {
      Text("Reading").font(.headline).accessibilityAddTraits(.isHeader)
      Text(subject?.primaryReadings.joined(separator: " · ") ?? "")
        .font(.largeTitle).textSelection(.enabled).accessibilityIdentifier("practice.reading")
    }
  }
  private func perform(_ operation: () throws -> Void) {
    error = nil
    do { try operation() } catch { self.error = error.localizedDescription }
  }
  private func present() {
    guard let practice else { return }
    screen.title = "Katakana practice"
    screen.question = practice.subject?.japanese ?? ""
    screen.prompt = "Reading"
    screen.questionKind = .reading
    screen.subjectColor = StudyPalette.vocabulary
    screen.completed = practice.session.completedIDs.count
    screen.remaining = practice.session.activeIDs.count + practice.session.queuedIDs.count
    screen.accuracy = "\(practice.session.successRate)%"
    screen.phase =
      practice.session.currentDecision == .incorrect
      ? (preferences.revealAnswers ? .details : .incorrect) : .answering
    screen.answer = ""
    screen.answerHint = nil
    screen.feedback = practice.session.currentDecision == .incorrect ? "Incorrect answer" : ""
    screen.success = nil
    screen.canShowAll = false
    screen.hasMenu = true
    screen.endTitle = "End practice"
    applyPreferences()
    customFont = fonts.fontNames(for: screen.question).randomElement() ?? ""
    chooseFont()
    focused = screen.phase != .details && !screen.isAnki
  }
  private func applyPreferences() {
    practice?.options = preferences.sessionOptions
    let wasAnki = screen.isAnki
    screen.isAnki = practice?.isAnki == true
    if wasAnki != screen.isAnki && practice?.session.currentDecision != .incorrect {
      screen.phase = .answering
    }
    screen.feedbackPreferences = preferences
    screen.questionSize = 72 * min(2.5, max(1, preferences.fontScale))
    screen.canSkip = preferences.allowSkipping
    screen.canOverride =
      preferences.allowCorrections && practice?.session.currentDecision == .incorrect
  }
  private func savePreferences(_ old: ReviewPreferences, _ new: ReviewPreferences) {
    perform { try $preferences.applyChanges(from: old, to: new) }
  }
  private func chooseFont() {
    let available = fonts.fontNames(for: screen.question)
    if !available.contains(customFont) { customFont = available.first ?? "" }
    screen.canChangeFont = !available.isEmpty
    screen.questionFont = screen.phase == .details ? "" : customFont
  }
  private func cycleFont(_ offset: Int) {
    let available = fonts.fontNames(for: screen.question)
    guard !available.isEmpty else { return }
    let index = available.firstIndex(of: customFont) ?? 0
    customFont = available[(index + offset + available.count) % available.count]
    chooseFont()
  }
  private func submit(convertRomaji: Bool = true) {
    guard let question = practice?.question else { return }
    let typed = screen.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else {
      if preferences.allowSkipping { act(.deferQuestion) }
      return
    }
    perform {
      guard let result = try practice?.answer(typed, for: question, convertRomaji: convertRomaji)
      else { return }
      switch result.grade {
      case .precise, .imprecise:
        present()
        if let success = result.success { screen.recordSuccess(success) }
      case .incorrect:
        present()
        screen.answer = result.normalized
      default:
        screen.answer = result.normalized
        screen.showAnswerHint(result.grade)
      }
    }
  }
  private func act(_ action: ReviewScreenAction) {
    switch action {
    case .end:
      focused = false
      voiceRequest = nil
      if practice?.session.completedIDs.isEmpty == false { ended = true } else { dismiss() }
      return
    case .settings:
      focused = false
      settings = true
      return
    default: break
    }
    guard let question = practice?.question else { return }
    perform {
      switch action {
      case .submit:
        if screen.isAnki {
          if screen.phase == .details {
            screen.showAssessment = true
          } else {
            screen.phase = .details
            focused = false
          }
        } else if screen.phase == .details || screen.phase == .incorrect {
          try practice?.advance(question)
          present()
        } else {
          submit()
        }
      case .reveal: screen.phase = .details
      case .retry:
        screen.phase = .answering
        screen.answer = ""
        screen.feedback = ""
        focused = !screen.isAnki
      case .correct:
        let success: StudyMarkResult?
        if screen.canOverride || (screen.isAnki && practice?.session.currentDecision == .incorrect)
        {
          success = try practice?.correct(question)
        } else if screen.isAnki && screen.phase == .details {
          success = try practice?.assess(correct: true, for: question)
        } else {
          return
        }
        present()
        if let success { screen.recordSuccess(success) }
      case .incorrect:
        guard screen.phase == .details else { return }
        if !screen.isAnki {
          try practice?.advance(question)
          present()
          return
        }
        if practice?.session.currentDecision == .incorrect {
          try practice?.advance(question)
        } else {
          try practice?.assess(correct: false, for: question)
        }
        present()
      case .deferQuestion:
        try practice?.deferQuestion(question)
        present()
      case .voice:
        guard !screen.isAnki else { return }
        focused = false
        voiceRequest = VoiceAnswerRequest(question: question)
      case .focus: focused = screen.phase == .answering && !screen.isAnki
      case .toggleFont:
        if screen.canChangeFont {
          screen.questionFont = screen.questionFont.isEmpty ? customFont : ""
        }
      case .nextFont: cycleFont(1)
      case .previousFont: cycleFont(-1)
      default: break
      }
    }
  }
}
