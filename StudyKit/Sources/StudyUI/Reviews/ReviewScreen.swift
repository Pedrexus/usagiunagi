import Observation
import StudyCore
import SwiftUI

/// Presentation state only. The host owns grading, persistence and platform input.
@MainActor @Observable public final class ReviewScreenState {
  public enum Phase { case answering, incorrect, details }
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
  public var canChangeFont = false
  public var showAssessment = false
  public var successCount = 0
  public var success: StudyMarkResult?
  public var feedbackPreferences = ReviewPreferences()
  public init() {}

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
  #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
  #endif
  private var compactLandscape: Bool {
    #if os(iOS)
      verticalSizeClass == .compact
    #else
      false
    #endif
  }
  @State private var confirmEnd = false
  @Bindable private var state: ReviewScreenState
  private let action: (ReviewScreenAction) -> Void
  private let input: () -> Input
  private let details: () -> Details
  private let questionContent: () -> QuestionContent

  public init(
    state: ReviewScreenState, action: @escaping (ReviewScreenAction) -> Void,
    @ViewBuilder input: @escaping () -> Input, @ViewBuilder details: @escaping () -> Details
  ) where QuestionContent == EmptyView {
    self.init(
      state: state, action: action, question: { EmptyView() }, input: input, details: details)
  }

  public init(
    state: ReviewScreenState, action: @escaping (ReviewScreenAction) -> Void,
    @ViewBuilder question: @escaping () -> QuestionContent,
    @ViewBuilder input: @escaping () -> Input, @ViewBuilder details: @escaping () -> Details
  ) {
    self.state = state
    self.action = action
    self.input = input
    self.details = details
    self.questionContent = question
  }

  public var body: some View {
    NavigationStack {
      Group {
        if compactLandscape {
          HStack(spacing: 16) {
            question
            VStack(spacing: 8) {
              progress
              response
            }
          }
        } else {
          VStack(spacing: 12) {
            progress
            question
            response
          }
        }
      }
      .padding()
      .navigationTitle(state.title ?? (state.hasMenu ? "Reviews" : "Quiz"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        if state.hasMenu {
          ToolbarItem(placement: .cancellationAction) {
            Button("End session", systemImage: "xmark") {
              if state.canWrapUp { confirmEnd = true } else { action(.end) }
            }
            .accessibilityIdentifier("review.close")
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
        Button("My answer was correct") { action(.correct) }
        Button("My answer was incorrect") { action(.incorrect) }
        Button("Ask again later") { action(.deferQuestion) }
      }
      .confirmationDialog(
        "End review session?", isPresented: $confirmEnd, titleVisibility: .visible
      ) {
        if state.wrappingUp {
          Button("Stop wrapping up") { action(.stopWrapping) }
        } else {
          Button("Wrap up (\(state.activeCount) to go)") { action(.wrap) }
        }
        Button("End review session", role: .destructive) { action(.end) }
      } message: {
        Text(
          "Ending now loses progress on half-answered reviews. Wrap up to finish the current batch first."
        )
      }
      .onChange(of: compactLandscape) { _, _ in action(.focus) }
      .sensoryFeedback(.success, trigger: state.successCount)
    }
  }

  private var progress: some View {
    VStack(spacing: 6) {
      HStack {
        Text("\(state.completed) completed · \(state.remaining) remaining")
          .accessibilityIdentifier("review.progress")
        Spacer()
        if let accuracy = state.accuracy { Label(accuracy, systemImage: "checkmark") }
      }.font(.caption).foregroundStyle(.secondary)
      ProgressView(
        value: Double(state.completed), total: Double(max(1, state.completed + state.remaining)))
      successFeedback
      if state.wrappingUp { Label("Wrapping up", systemImage: "clock").font(.caption) }
    }.accessibilityElement(children: .contain)
  }

  private var successFeedback: some View {
    ViewThatFits(in: .horizontal) {
      feedbackLabels(horizontal: true)
      feedbackLabels(horizontal: false)
    }
    .font(.caption).foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("review.success")
  }

  private func feedbackLabels(horizontal: Bool) -> some View {
    let layout =
      horizontal
      ? AnyLayout(HStackLayout(spacing: 12))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
    return layout {
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
    .symbolEffectsRemoved(reduceMotion)
    .symbolEffect(.bounce, options: .nonRepeating, value: state.successCount)
  }

  @ViewBuilder private var response: some View {
    if state.phase == .details {
      if !state.isAnki && !state.answer.isEmpty {
        Text("Your answer: " + state.answer).font(.callout).foregroundStyle(.red)
          .lineLimit(2).accessibilityIdentifier("review.previousAnswer")
      }
      details()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack {
        if state.canShowAll {
          Button("All information", systemImage: "info.circle") { action(.showAll) }
        }
        Spacer()
        if state.canPlayAudio {
          Button("Audio", systemImage: "speaker.wave.2") { action(.playAudio) }
        }
      }.font(.callout)
      answerActions
    } else {
      if !state.feedback.isEmpty {
        Text(state.feedback).font(.callout).foregroundStyle(.red)
          .accessibilityIdentifier("review.feedback")
      }
      if state.phase == .incorrect {
        HStack {
          Button("Try again", systemImage: "arrow.counterclockwise") { action(.retry) }
          Button("Reveal answer", systemImage: "eye") { action(.reveal) }
            .accessibilityIdentifier("review.reveal")
        }.buttonStyle(.bordered)
      }
      if !state.isAnki { input().disabled(!state.canAnswer).frame(minHeight: 48, maxHeight: 56) }
      Button(
        state.phase == .incorrect
          ? "Continue"
          : state.isAnki
            ? "Show answer"
            : state.canSkip && state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "Skip" : "Check answer"
      ) {
        action(.submit)
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        !state.canAnswer
          || (state.phase == .answering && !state.isAnki && !state.canSkip && state.answer.isEmpty)
      )
      .accessibilityIdentifier("review.submit")
    }
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
        .gesture(
          DragGesture(minimumDistance: 40).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) {
              action(value.translation.width < 0 ? .nextFont : .previousFont)
            }
          })
        if !state.previous.isEmpty && state.phase == .answering {
          Button("Previous: " + state.previous, systemImage: "clock.arrow.circlepath") {
            action(.previous)
          }
          .font(.caption)
        }
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
    .frame(maxWidth: .infinity, maxHeight: state.phase == .details ? 170 : .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private var answerActions: some View {
    HStack {
      if state.isAnki {
        Button("Incorrect", systemImage: "xmark") { action(.incorrect) }
          .accessibilityIdentifier("review.incorrect")
        Button("Correct", systemImage: "checkmark") { action(.correct) }
          .buttonStyle(.borderedProminent).accessibilityIdentifier("review.correct")
      } else {
        Button("Continue", systemImage: "arrow.right") { action(.submit) }
          .buttonStyle(.borderedProminent).accessibilityIdentifier("review.submit")
      }
      if state.canOverride || state.isAnki {
        Menu("Correct answer", systemImage: "ellipsis") {
          Button("My answer was correct") { action(.correct) }
          Button("Ask again later") { action(.deferQuestion) }
          if state.canExclude { Button("Exclude this item") { action(.exclude) } }
          if state.canAddSynonym { Button("Add synonym") { action(.synonym) } }
        }.accessibilityIdentifier("review.corrections")
      }
    }.buttonStyle(.bordered)
  }
}
