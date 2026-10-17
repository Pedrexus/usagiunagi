import StudyCore
import StudyPersistence
import SwiftUI

/// Native offline reviews. The store commits each decision before the next question is shown.
public struct NativeReviewView: View {
  private let store: StudyStore
  private let accountID: String
  @State private var review: NativeReviewState?
  @State private var screen = ReviewScreenState()
  @State private var busy = false
  @State private var error: String?
  @State private var voice = false
  @State private var confirmEnd = false
  @State private var readyImage: String?
  @State private var voiceQuestion: StudyQuestion?
  @FocusState private var answerFocused: Bool

  public init(store: StudyStore, accountID: String) {
    self.store = store
    self.accountID = accountID
  }

  public var body: some View {
    VStack {
      if let review {
        if review.question != nil {
          HStack {
            Spacer()
            Button("End session", systemImage: "xmark") { confirmEnd = true }
          }.padding(.horizontal)
        }
        if review.question == nil {
          ContentUnavailableView(
            "Review session saved", systemImage: "checkmark.circle",
            description: Text(
              "\(review.saved.session.completedIDs.count) completed · \(review.saved.session.successRate)% accuracy. Completed answers stay on this Mac until you sync Saved work."
            ))
          Button("Finish session") {
            run {
              try await store.finishReviews(
                accountID: accountID, expectedRevision: review.saved.revision)
              self.review = nil
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
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                LabeledContent(
                  "Meaning",
                  value: subject.meanings.filter { $0.role != .blacklist }.map(\.text).joined(
                    separator: ", "))
                LabeledContent(
                  "Reading", value: subject.readings.map(\.text).joined(separator: " · "))
                if let url = URL(string: subject.documentURL), url.scheme == "https",
                  url.host == "www.wanikani.com"
                {
                  Link("Full subject information on WaniKani", destination: url)
                }
              }.padding().textSelection(.enabled)
            }
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
          "Offline reviews", systemImage: "rectangle.and.pencil.and.ellipsis",
          description: Text(
            "Start with the reviews due in your saved account, or resume the session already saved on this Mac."
          ))
        Button("Start or resume reviews") { load() }.buttonStyle(.borderedProminent)
      }
      if busy { ProgressView("Saving") }
      if let error {
        Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
        Button("Reload saved session") { load() }
      }
    }
    .disabled(busy)
    .confirmationDialog("End review session?", isPresented: $confirmEnd, titleVisibility: .visible)
    {
      if let review {
        Button("End session", role: .destructive) {
          run {
            try await store.endReviews(
              accountID: accountID, expectedRevision: review.saved.revision)
            self.review = nil
          }
        }
      }
    } message: {
      Text("Completed answers stay saved. Progress on unfinished subjects will be discarded.")
    }
    .sheet(isPresented: $voice) {
      if let question = voiceQuestion {
        VoiceAnswerPanel(question: question) { text in
          voice = false
          guard review?.question == question else { return }
          screen.answer = text
          submit(convertRomaji: false)
        } cancel: {
          voice = false
        }
        .frame(minWidth: 420, minHeight: 440)
      }
    }
    .task(id: accountID) { load() }
  }

  private func load() {
    run { present(try await store.openReviews(accountID: accountID)) }
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
    review = value
    let session = value.saved.session
    screen.title = "Reviews"
    screen.question = value.subject?.japanese ?? ""
    screen.canAnswer =
      !screen.question.isEmpty
      || (readyImage != nil && readyImage == value.subject?.characterImageURL)
    screen.prompt = value.question?.kind == .reading ? "Reading" : "Meaning"
    screen.subjectColor =
      value.subject?.kind == .kanji
      ? StudyPalette.kanji
      : value.subject?.kind == .radical ? StudyPalette.radical : StudyPalette.vocabulary
    screen.level = value.subject.map { "Level \($0.level)" } ?? ""
    screen.completed = session.completedIDs.count
    screen.remaining = session.activeIDs.count + session.queuedIDs.count
    screen.accuracy = "\(session.successRate)%"
    screen.wrappingUp = session.wrappingUp
    screen.phase = session.currentDecision == .incorrect ? .incorrect : .answering
    screen.canOverride = session.currentDecision == .incorrect
    screen.answer = ""
    screen.feedback =
      session.currentDecision == .incorrect ? "Incorrect answer. Try again or reveal it." : ""
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
    guard !typed.isEmpty else { return }
    let answer =
      question.kind == .reading && convertRomaji ? KanaConverter.convert(typed).text : typed
    run {
      let result = try await store.answerReview(
        answer, question: question, accountID: accountID, expectedRevision: review.saved.revision)
      present(result.state)
      if result.state.question == question { screen.answer = result.normalized }
      switch result.grade {
      case .precise, .imprecise: screen.successCount += 1
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
    case .reveal, .showAll: screen.phase = .details
    case .retry:
      screen.phase = .answering
      screen.answer = ""
      screen.feedback = ""
      answerFocused = true
    case .correct: change(.overrideCorrect)
    case .deferQuestion: change(.deferQuestion)
    case .voice:
      voiceQuestion = review?.question
      voice = voiceQuestion != nil
    case .focus: answerFocused = true
    default: break
    }
  }
}
