import StudyCore
import SwiftUI

/// An account-independent practice entry point shared by native hosts.
public struct KatakanaPracticeView: View {
  @State private var practicing = false
  public init() {}
  public var body: some View {
    KatakanaPracticeMenu { practicing = true }
      .sheet(isPresented: $practicing) { KatakanaPracticeSessionView() }
  }
}

/// The legacy iOS host retains its study options while sharing the native practice menu.
public struct KatakanaPracticeMenu: View {
  private let start: () -> Void
  public init(start: @escaping () -> Void) { self.start = start }
  public var body: some View {
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

private struct KatakanaPracticeSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @StoredReviewPreferences private var preferences
  @State private var practice: KatakanaPractice?
  @State private var screen = ReviewScreenState()
  @State private var error: String?
  @State private var confirmEnd = false
  @State private var voiceRequest: VoiceAnswerRequest?
  @FocusState private var focused: Bool

  var body: some View {
    VStack {
      HStack {
        Text("Practice only · WaniKani progress is unchanged").font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        #if os(macOS)
          if practice?.question != nil && screen.phase == .answering {
            Button("Voice answer", systemImage: "mic") { act(.voice) }
              .labelStyle(.iconOnly).accessibilityIdentifier("practice.voice")
          }
        #endif
        Button("End practice", systemImage: "xmark") {
          if practice?.question == nil { dismiss() } else { confirmEnd = true }
        }.accessibilityIdentifier("practice.end")
      }.padding(.horizontal).padding(.vertical, 8)
      if let practice, practice.question == nil {
        ContentUnavailableView(
          "Practice complete", systemImage: "checkmark.circle",
          description: Text(
            "\(practice.session.completedIDs.count) completed · \(practice.session.successRate)% accuracy"
          ))
        Button("Practice again") { start() }.buttonStyle(.borderedProminent)
        Button("Done") { dismiss() }
      } else if practice != nil {
        ReviewScreen(state: screen, action: act) {
          TextField("Reading", text: $screen.answer)
            .textFieldStyle(.roundedBorder).font(.title2).autocorrectionDisabled()
            .focused($focused).onSubmit { act(.submit) }
            .accessibilityIdentifier("review.answer")
        } details: {
          VStack {
            Text("Reading").font(.headline).accessibilityAddTraits(.isHeader)
            Text(practice?.subject?.primaryReadings.joined(separator: " · ") ?? "")
              .font(.largeTitle).textSelection(.enabled)
          }
        }
      }
      if let error { Text(error).foregroundStyle(.red).padding() }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 480)
    #endif
    .interactiveDismissDisabled(practice?.question != nil)
    .confirmationDialog("End practice?", isPresented: $confirmEnd, titleVisibility: .visible) {
      Button("End practice", role: .destructive) { dismiss() }
    } message: {
      Text("This practice session will be discarded. Your WaniKani reviews stay unchanged.")
    }
    .sheet(item: $voiceRequest) { request in
      VoiceAnswerPanel(question: request.question) { answer in
        voiceRequest = nil
        guard practice?.question == request.question else { return }
        screen.answer = answer
        submit(convertRomaji: false)
      } cancel: {
        voiceRequest = nil
      }
      #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
      #endif
    }
    .task { if practice == nil { start() } }
    .onChange(of: preferences) { _, _ in applyPreferences() }
  }

  private func start() {
    perform {
      practice = try KatakanaPractice()
      present()
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
    screen.subjectColor = StudyPalette.vocabulary
    screen.completed = practice.session.completedIDs.count
    screen.remaining = practice.session.activeIDs.count + practice.session.queuedIDs.count
    screen.accuracy = "\(practice.session.successRate)%"
    screen.phase =
      practice.session.currentDecision == .incorrect
      ? (preferences.revealAnswers ? .details : .incorrect) : .answering
    screen.answer = ""
    screen.feedback = practice.session.currentDecision == .incorrect ? "Incorrect answer" : ""
    screen.canShowAll = false
    applyPreferences()
    focused = screen.phase == .answering
  }
  private func applyPreferences() {
    screen.questionSize = 72 * min(2.5, max(1, preferences.fontScale))
    screen.canSkip = preferences.allowSkipping
    screen.canOverride =
      preferences.allowCorrections && practice?.session.currentDecision == .incorrect
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
        screen.successCount += 1
        present()
      case .incorrect:
        present()
        screen.answer = result.normalized
      default:
        screen.answer = result.normalized
        screen.feedback = "Enter the reading in kana."
      }
    }
  }
  private func act(_ action: ReviewScreenAction) {
    guard let question = practice?.question else { return }
    perform {
      switch action {
      case .submit:
        if screen.phase == .details {
          try practice?.advance(question)
          present()
        } else if screen.phase == .incorrect {
          screen.phase = .details
        } else {
          submit()
        }
      case .reveal: screen.phase = .details
      case .retry:
        screen.phase = .answering
        screen.answer = ""
        screen.feedback = ""
        focused = true
      case .correct:
        if screen.canOverride {
          try practice?.correct(question)
          present()
        }
      case .deferQuestion:
        try practice?.deferQuestion(question)
        present()
      case .voice:
        voiceRequest = VoiceAnswerRequest(question: question)
      case .focus: focused = true
      default: break
      }
    }
  }
}
