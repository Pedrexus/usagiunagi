import Foundation
import Observation
import StudyCore
import SwiftUI

/// Presentation state only. The host owns grading, persistence and platform input.
@MainActor @Observable public final class ReviewScreenState {
  public enum Phase: String { case answering, incorrect, details }
  public var phase = Phase.answering
  public var question = ""
  public var questionImage: Image?
  public var questionFont = ""
  public var questionSize: Double = 72
  public var prompt = ""
  public var questionKind = StudyQuestionKind.meaning
  public var title: String?
  public var canAnswer = true
  public var subjectColor = Color.accentColor
  public var level = ""
  public var stage = ""
  public var stageAccessibility = ""
  public var answer = ""
  public var feedback = ""
  public var answerHint: AttributedString?
  public var previous = ""
  public var completed = 0
  public var remaining = 0
  public var accuracy: String?
  public var wrappingUp = false
  public var canWrapUp = false
  public var activeCount = 0
  public var isAnki = false
  public var canSkip = false
  public var canOverride = false
  public var canExclude = false
  public var canAddSynonym = false
  public var canPlayAudio = false
  public var canShowAll = true
  public var hasMenu = false
  public var endTitle = "End review session"
  public var canChangeFont = false
  public var showAssessment = false
  public var successCount = 0
  public var success: StudyMarkResult?
  public var feedbackPreferences = ReviewPreferences()
  public init() {}

  /// Keep UTF-16 grading ranges attached to the exact normalized answer shown to the learner.
  public func showAnswerHint(_ grade: AnswerGrade, exactMatch: Bool = false) {
    answerHint = nil
    let ranges: [NSRange]
    switch grade {
    case .mismatchingOkurigana(let value):
      feedback = "Check the kana following the kanji."
      ranges = value
    case .containsInvalidCharacters(let value):
      feedback = "Check the highlighted characters."
      ranges = value
    case .otherKanjiReading:
      feedback = "Use the reading taught for this subject."
      return
    case .isReadingButWantMeaning:
      feedback = "Enter the meaning. Your reading was correct."
      return
    case .imprecise where exactMatch:
      feedback = "Use the exact meaning."
      return
    default: return
    }
    var highlighted = AttributedString(answer)
    for range in ranges {
      guard let source = Range(range, in: answer),
        let lower = AttributedString.Index(source.lowerBound, within: highlighted),
        let upper = AttributedString.Index(source.upperBound, within: highlighted)
      else { continue }
      highlighted[lower..<upper].foregroundColor = .red
      highlighted[lower..<upper].underlineStyle = .single
    }
    answerHint = highlighted
  }

  public func recordSuccess(_ mark: StudyMarkResult) {
    success = mark
    successCount += 1
  }
}

public enum ReviewScreenAction {
  case end, wrap, stopWrapping, settings, voice, submit, reveal, retry, correct, incorrect,
    deferQuestion, exclude
  case synonym, previous, toggleFont, nextFont, previousFont, showAll, playAudio, focus
}

/// Shared review layout; native input and rich details are supplied by each host during migration.
public struct ReviewScreen<Input: View, Details: View, QuestionContent: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var confirmEnd = false
  @Bindable private var state: ReviewScreenState
  private let audio: StudyAudioLibrary?
  private let action: (ReviewScreenAction) -> Void
  private let input: () -> Input
  private let details: () -> Details
  private let questionContent: () -> QuestionContent

  public init(
    state: ReviewScreenState, audio: StudyAudioLibrary? = nil,
    action: @escaping (ReviewScreenAction) -> Void,
    @ViewBuilder input: @escaping () -> Input, @ViewBuilder details: @escaping () -> Details
  ) where QuestionContent == EmptyView {
    self.init(
      state: state, audio: audio, action: action, question: { EmptyView() }, input: input,
      details: details)
  }

  public init(
    state: ReviewScreenState, audio: StudyAudioLibrary? = nil,
    action: @escaping (ReviewScreenAction) -> Void,
    @ViewBuilder question: @escaping () -> QuestionContent,
    @ViewBuilder input: @escaping () -> Input, @ViewBuilder details: @escaping () -> Details
  ) {
    self.state = state
    self.audio = audio
    self.action = action
    self.input = input
    self.details = details
    self.questionContent = question
  }

  public var body: some View {
    GeometryReader { viewport in
      ScrollView {
        VStack(spacing: 12) {
          progress
          if let audio { AudioPlaybackNotice(library: audio) }
          let horizontal =
            viewport.size.width >= 560 && viewport.size.height < 420
            && !typeSize.isAccessibilitySize
          let layout =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 16))
            : AnyLayout(VStackLayout(spacing: 12))
          layout {
            question
            VStack(spacing: 12) { response }
              .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
          }
        }.frame(maxWidth: 760, minHeight: viewport.size.height, alignment: .top)
          .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.never)
      .accessibilityIdentifier("review.scroll")
    }
    .padding()
    .safeAreaInset(edge: .bottom) {
      if state.phase == .details {
        answerActions.padding().frame(maxWidth: 760).frame(maxWidth: .infinity).background(.bar)
      }
    }
    .navigationTitle(state.title ?? (state.hasMenu ? "Reviews" : "Quiz"))
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      if state.hasMenu {
        ToolbarItem(placement: .cancellationAction) {
          Button("End session", systemImage: "xmark") {
            if state.canWrapUp { confirmEnd = true } else { action(.end) }
          }
          .accessibilityIdentifier("review.close")
        }
      }
      ToolbarItem(placement: .secondaryAction) {
        if state.canChangeFont || !state.previous.isEmpty {
          Menu("Review actions", systemImage: "ellipsis") {
            if !state.previous.isEmpty {
              Button("Previous subject") { action(.previous) }.keyboardShortcut(
                "p", modifiers: .command)
            }
            if state.canChangeFont {
              Button("Toggle question font") { action(.toggleFont) }.keyboardShortcut(
                .tab, modifiers: .option)
              Button("Next font") { action(.nextFont) }.keyboardShortcut(
                .rightArrow, modifiers: [.command, .option])
              Button("Previous font") { action(.previousFont) }.keyboardShortcut(
                .leftArrow, modifiers: [.command, .option])
            }
          }
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        if state.phase == .answering && !state.isAnki {
          Button("Voice answer", systemImage: "mic") { action(.voice) }
            .accessibilityIdentifier("review.voice").disabled(!state.canAnswer)
        }
        if state.hasMenu {
          Button("Quick settings", systemImage: "slider.horizontal.3") { action(.settings) }
            .accessibilityIdentifier("review.settings")
        }
      }
    }
    .confirmationDialog("Check your answer", isPresented: $state.showAssessment) {
      correctionActions
    }
    .confirmationDialog(
      state.endTitle + "?", isPresented: $confirmEnd, titleVisibility: .visible
    ) {
      if state.wrappingUp {
        Button("Stop wrapping up") { action(.stopWrapping) }
      } else {
        Button("Wrap up (\(state.activeCount) to go)") { action(.wrap) }
      }
      Button(state.endTitle, role: .destructive) { action(.end) }
    } message: {
      Text(
        "Completed answers stay saved. Ending now discards unfinished answers. Wrap up to finish the current batch first."
      )
    }
    .sensoryFeedback(.success, trigger: state.successCount)
  }

  private var progress: some View {
    VStack(spacing: 6) {
      adaptiveControls {
        Text("\(state.completed) completed · \(state.remaining) remaining")
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("review.progress")
        if let accuracy = state.accuracy { Label(accuracy, systemImage: "checkmark") }
      }.font(.caption).foregroundStyle(.secondary)
      ProgressView(
        value: Double(state.completed), total: Double(max(1, state.completed + state.remaining)))
      successFeedback
      if state.wrappingUp { Label("Wrapping up", systemImage: "clock").font(.caption) }
      if !state.previous.isEmpty && state.phase == .answering {
        Button("Previous: " + state.previous, systemImage: "clock.arrow.circlepath") {
          action(.previous)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
      }
    }.accessibilityElement(children: .contain)
  }

  private var successFeedback: some View {
    adaptiveControls {
      if let success = state.success {
        if state.feedbackPreferences.correctAnswerFeedback {
          Label("Correct", systemImage: "checkmark.circle")
            .accessibilityLabel("Previous answer correct")
        }
        if success.subjectFinished, state.feedbackPreferences.completedItemFeedback {
          Label("+1 completed", systemImage: "plus.circle")
        }
        if let milestone = success.estimatedMilestone,
          state.feedbackPreferences.srsMilestoneFeedback
        {
          Label("\(milestone) (estimate)", systemImage: "arrow.up.circle")
            .accessibilityLabel("Estimated SRS stage: \(milestone). Sync to confirm.")
        }
      }
    }
    .font(.caption).foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("review.success")
    .symbolEffectsRemoved(reduceMotion)
    .symbolEffect(.bounce, options: .nonRepeating, value: state.successCount)
  }

  @ViewBuilder private var response: some View {
    if state.phase == .details {
      if !state.isAnki && !state.answer.isEmpty {
        Text("Your answer: " + state.answer).font(.callout).foregroundStyle(.red)
          .accessibilityIdentifier("review.previousAnswer")
      }
      details().frame(maxWidth: .infinity, alignment: .leading)
      adaptiveControls {
        if state.canShowAll {
          Button("All information", systemImage: "info.circle") { action(.showAll) }
            .keyboardShortcut(.space, modifiers: [])
        }
        if state.canPlayAudio {
          Button("Audio", systemImage: "speaker.wave.2") { action(.playAudio) }
            .keyboardShortcut("j", modifiers: [])
        }
      }.font(.callout)
    } else {
      if !state.isAnki { input().disabled(!state.canAnswer).frame(minHeight: 48) }
      if !state.feedback.isEmpty {
        Text(state.feedback).font(.callout).foregroundStyle(.red)
          .accessibilityIdentifier("review.feedback")
      }
      if let hint = state.answerHint, String(hint.characters) == state.answer {
        Text(hint).font(.title3)
          .accessibilityIdentifier("review.answerHint")
      }
      Button {
        action(.submit)
      } label: {
        Text(submitTitle).frame(maxWidth: .infinity, minHeight: 24)
      }
      .buttonStyle(.borderedProminent).controlSize(.large)
      .disabled(
        !state.canAnswer
          || (state.phase == .answering && !state.isAnki && !state.canSkip && state.answer.isEmpty)
      )
      .accessibilityIdentifier("review.submit")
      .keyboardShortcut(state.isAnki || state.phase == .incorrect ? .defaultAction : nil)
      if state.phase == .incorrect {
        adaptiveControls {
          Button("Try again", systemImage: "arrow.counterclockwise") { action(.retry) }
            .keyboardShortcut(.delete, modifiers: [])
          Button("Reveal answer", systemImage: "eye") { action(.reveal) }
            .accessibilityIdentifier("review.reveal")
            .keyboardShortcut("f", modifiers: [])
        }.buttonStyle(.bordered).controlSize(.large)
      }
    }
  }

  private var submitTitle: String {
    if state.phase == .incorrect { return "Continue" }
    if state.isAnki { return "Show answer" }
    return state.canSkip && state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Skip" : "Check answer"
  }

  private var question: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Group {
          if let image = state.questionImage {
            image.resizable().scaledToFit().frame(maxHeight: state.questionSize)
          } else if state.question.isEmpty {
            questionContent().frame(maxHeight: state.questionSize)
          } else {
            Text(state.question)
              .font(
                state.questionFont.isEmpty
                  ? .system(size: state.questionSize)
                  : .custom(state.questionFont, size: state.questionSize)
              )
              .minimumScaleFactor(0.25).lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: state.phase == .details ? 70 : .infinity)
        .accessibilityLabel("Japanese question")
        .accessibilityValue(state.question)
        .accessibilityIdentifier("review.question")
        .contentShape(Rectangle())
        .onTapGesture {
          if state.isAnki && state.phase == .answering {
            action(.submit)
          } else {
            action(.toggleFont)
          }
        }
        .simultaneousGesture(
          DragGesture(minimumDistance: 40).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) {
              action(value.translation.width < 0 ? .nextFont : .previousFont)
            }
          })
      }.padding().foregroundStyle(.white).tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(state.subjectColor)
      VStack(spacing: 4) {
        Text(state.prompt).font(.headline).accessibilityIdentifier("review.prompt")
        HStack {
          if !state.level.isEmpty { Text(state.level) }
          if !state.stage.isEmpty { Text(state.stage).accessibilityLabel(state.stageAccessibility) }
        }.font(.caption)
      }.padding(8).frame(maxWidth: .infinity)
        .foregroundStyle(state.questionKind == .reading ? Color.white : Color.primary)
        .background {
          if state.questionKind == .reading {
            Color(white: 0.12)
          } else {
            Rectangle().fill(.background)
          }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: state.phase == .details ? nil : .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func adaptiveControls<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8, content: content).fixedSize(horizontal: true, vertical: false)
      VStack(alignment: .leading, spacing: 8, content: content)
    }
  }

  private var answerActions: some View {
    VStack(spacing: 12) {
      if state.isAnki {
        adaptiveControls {
          Button("Incorrect", systemImage: "xmark") { action(.incorrect) }
            .accessibilityIdentifier("review.incorrect")
            .keyboardShortcut("i", modifiers: .control)
          Button("Correct", systemImage: "checkmark") { action(.correct) }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("review.correct")
            .keyboardShortcut("c", modifiers: .control)
        }
      } else {
        Button {
          action(.submit)
        } label: {
          Label("Continue", systemImage: "arrow.right")
            .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.borderedProminent).accessibilityIdentifier("review.submit")
        .keyboardShortcut(.defaultAction)
      }
      if state.canOverride || state.isAnki {
        Group {
          if state.isAnki {
            Menu("Assess answer", systemImage: "ellipsis") {
              correctionActions
            } primaryAction: {
              action(.submit)
            }
            .keyboardShortcut(.defaultAction)
          } else {
            Menu("Correct answer", systemImage: "ellipsis") { correctionActions }
          }
        }.accessibilityIdentifier("review.corrections")
      }
    }.buttonStyle(.bordered).controlSize(.large)
  }

  @ViewBuilder private var correctionActions: some View {
    // Preserve standard Copy/Select All; grading shortcuts use Control.
    Button("My answer was correct") { action(.correct) }
      .keyboardShortcut("c", modifiers: .control)
    Button(state.isAnki ? "My answer was incorrect" : "Keep answer incorrect") {
      action(.incorrect)
    }.keyboardShortcut("i", modifiers: .control)
    Button("Ask again later") { action(.deferQuestion) }
      .keyboardShortcut("a", modifiers: .control)
    if state.canExclude {
      Button("Exclude this item") { action(.exclude) }.accessibilityIdentifier("review.exclude")
    }
    if state.canAddSynonym {
      Button("Add synonym") { action(.synonym) }.keyboardShortcut("s", modifiers: .command)
    }
  }
}
