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
  public var subjectType = ""
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
  public var voiceEnabled = false
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
  /// Nil preserves local milestone-only behavior; WaniKani can enable all completed stages.
  public var completedSrsChanges: Bool?
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

/// Shared review layout; hosts supply native input and rich subject details.
public struct ReviewScreen<Input: View, Details: View, QuestionContent: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var confirmEnd = false
  @Bindable private var state: ReviewScreenState
  private let action: (ReviewScreenAction) -> Void
  private let input: () -> Input
  private let details: () -> Details
  private let questionContent: () -> QuestionContent

  public init(
    state: ReviewScreenState,
    action: @escaping (ReviewScreenAction) -> Void,
    @ViewBuilder input: @escaping () -> Input, @ViewBuilder details: @escaping () -> Details
  ) where QuestionContent == EmptyView {
    self.init(
      state: state, action: action, question: { EmptyView() }, input: input,
      details: details)
  }

  public init(
    state: ReviewScreenState,
    action: @escaping (ReviewScreenAction) -> Void,
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
    GeometryReader { viewport in
      if state.phase == .details {
        ScrollView {
          VStack(spacing: 0) {
            progress.padding(.horizontal, 12).padding(.vertical, 6)
            studyStatus()
            question()
            VStack(spacing: 8) { response }.padding(12).frame(maxWidth: .infinity)
          }.frame(maxWidth: 760, minHeight: viewport.size.height, alignment: .top)
            .frame(maxWidth: .infinity)
        }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.never)
          .accessibilityIdentifier("review.scroll")
      } else {
        let horizontal = viewport.size.width >= 560 && viewport.size.height < 420
        let inline = viewport.size.height < 140
        let layout =
          horizontal ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 0))
        let questionLayout =
          inline ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
          questionLayout {
            if inline {
              studyStatus(inline: true).labelStyle(.iconOnly).fixedSize()
            } else {
              studyStatus()
            }
            question(compact: viewport.size.height < 420, inline: inline)
          }
          Group {
            if state.phase == .answering && state.feedback.isEmpty {
              VStack(spacing: 8) { response }
            } else {
              ScrollView { VStack(spacing: 8) { response } }
                .accessibilityIdentifier("review.answerScroll")
            }
          }.padding(.horizontal, 12).padding(.vertical, horizontal ? 0 : 12)
            .frame(maxWidth: .infinity).background(.bar)
            .controlSize(
              horizontal && inline && typeSize >= .accessibility3
                ? .small : .regular)
        }.frame(maxWidth: 760, maxHeight: .infinity).frame(maxWidth: .infinity)
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        if state.phase == .details { answerActions.padding(12) }
        studyTools.padding(.horizontal, 12)
      }.frame(maxWidth: 760).frame(maxWidth: .infinity).background(.bar)
        .accessibilityElement(children: .contain).accessibilityLabel("Study controls")
        .accessibilityIdentifier("review.controls")
    }
    .navigationTitle(state.title ?? (state.hasMenu ? "Reviews" : "Quiz"))
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      if state.hasMenu {
        ToolbarItem(placement: .cancellationAction) {
          Button("End session", systemImage: "xmark") {
            state.voiceEnabled = false
            if state.canWrapUp { confirmEnd = true } else { action(.end) }
          }
          .accessibilityIdentifier("review.close")
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
        if let accuracy = state.accuracy {
          Label(accuracy, systemImage: "hand.thumbsup").accessibilityLabel("Accuracy \(accuracy)")
        }
        Label("\(state.completed)", systemImage: "checkmark")
          .accessibilityLabel("\(state.completed) completed")
        Label("\(state.remaining)", systemImage: "tray")
          .accessibilityLabel("\(state.remaining) remaining")
      }.font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.progress")
      ProgressView(
        value: Double(state.completed), total: Double(max(1, state.completed + state.remaining))
      )
      .accessibilityHidden(true)
    }.accessibilityElement(children: .contain)
  }

  private func studyStatus(inline: Bool = false) -> some View {
    let layout =
      inline ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
    return layout {
      successFeedback(inline: inline)
      if state.wrappingUp { Label("Wrapping up", systemImage: "clock").font(.caption) }
    }.padding(.horizontal, inline ? 0 : 12)
  }

  private typealias SuccessNotice = (title: String, symbol: String, spoken: String)

  private var successNotices: [SuccessNotice] {
    guard let success = state.success else { return [] }
    var notices: [SuccessNotice] = []
    if state.feedbackPreferences.correctAnswerFeedback {
      notices.append(("Correct", "checkmark.circle", "Previous answer correct"))
    }
    if success.subjectFinished, state.feedbackPreferences.completedItemFeedback {
      notices.append(("+1 completed", "plus.circle", "+1 completed"))
    }
    if state.completedSrsChanges == true, success.subjectFinished, success.submission != nil,
      let stage = StudySRSStage(rawValue: success.estimatedSRSStage)
    {
      notices.append(
        (
          "\(stage.name) (estimate)", success.didLevelUp ? "arrow.up.circle" : "arrow.down.circle",
          "Estimated SRS stage: \(stage.name). Sync to confirm."
        ))
    } else if state.completedSrsChanges == nil, let milestone = success.estimatedMilestone,
      state.feedbackPreferences.srsMilestoneFeedback
    {
      notices.append(
        (
          "\(milestone) (estimate)", "arrow.up.circle",
          "Estimated SRS stage: \(milestone). Sync to confirm."
        ))
    }
    return notices
  }

  private func successFeedback(inline: Bool) -> some View {
    let notices = successNotices
    return Group {
      if inline, let summary = notices.last {
        Label(notices.map { $0.title }.joined(separator: " · "), systemImage: summary.symbol)
          .accessibilityLabel(notices.map { $0.spoken }.joined(separator: ", "))
      } else {
        adaptiveControls {
          ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
            Label(notice.title, systemImage: notice.symbol).accessibilityLabel(notice.spoken)
          }
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
    } else {
      if state.phase == .answering && !state.isAnki {
        if state.voiceEnabled {
          input().disabled(!state.canAnswer)
        } else {
          HStack(spacing: 8) {
            input().disabled(!state.canAnswer).fixedSize(horizontal: false, vertical: true)
              .frame(minHeight: 44)
            submitButton.labelStyle(.iconOnly)
          }
        }
      } else if !state.isAnki {
        input().disabled(!state.canAnswer).fixedSize(horizontal: false, vertical: true)
          .frame(minHeight: 44)
      }
      if !state.feedback.isEmpty {
        Text(state.feedback).font(.callout).foregroundStyle(.red)
          .accessibilityIdentifier("review.feedback")
      }
      if let hint = state.answerHint, String(hint.characters) == state.answer {
        Text(hint).font(.title3)
          .accessibilityIdentifier("review.answerHint")
      }
      if state.isAnki || state.phase == .incorrect { submitButton }
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

  private var submitButton: some View {
    Button {
      action(.submit)
    } label: {
      Label(submitTitle, systemImage: state.isAnki ? "eye" : "arrow.right")
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.glassProminent)
    .disabled(
      !state.canAnswer
        || (state.phase == .answering && !state.isAnki && !state.canSkip && state.answer.isEmpty)
    )
    .accessibilityIdentifier("review.submit")
    .keyboardShortcut(state.isAnki || state.phase == .incorrect ? .defaultAction : nil)
  }

  // The keyboard safe area also keeps these tools available with hardware keyboards and on Mac.
  private var studyTools: some View {
    HStack(spacing: 12) {
      if (state.phase == .answering || state.voiceEnabled) && !state.isAnki {
        Button {
          action(.voice)
        } label: {
          toolLabel(
            state.voiceEnabled ? "Pause voice review" : "Voice review",
            systemImage: state.voiceEnabled ? "mic.slash" : "mic")
        }.accessibilityIdentifier("review.voice").disabled(!state.canAnswer)
      }
      Button {
        action(.deferQuestion)
      } label: {
        toolLabel("Ask later", systemImage: "arrow.uturn.forward")
      }.accessibilityIdentifier("review.defer")
      if state.canPlayAudio && state.phase == .details {
        Button {
          action(.playAudio)
        } label: {
          toolLabel("Audio", systemImage: "speaker.wave.2")
        }.accessibilityIdentifier("review.audio").keyboardShortcut("j", modifiers: [])
      }
      if state.phase == .details && state.canShowAll {
        Button {
          action(.showAll)
        } label: {
          toolLabel("All information", systemImage: "info.circle")
        }.accessibilityIdentifier("review.showAll").keyboardShortcut(.space, modifiers: [])
      }
      Spacer()
      if state.phase != .details { compactProgress }
      Menu {
        if !state.level.isEmpty || !state.stage.isEmpty {
          Section(state.subjectType.isEmpty ? "Subject" : state.subjectType) {
            Text([state.level, state.stage].filter { !$0.isEmpty }.joined(separator: " · "))
              .accessibilityLabel(
                [state.level, state.stageAccessibility].filter { !$0.isEmpty }.joined(
                  separator: ", "))
          }
        }
        if !state.previous.isEmpty {
          Button("Previous: " + state.previous, systemImage: "clock.arrow.circlepath") {
            action(.previous)
          }.keyboardShortcut("p", modifiers: .command)
        }
        if state.canChangeFont {
          Button("Toggle question font") { action(.toggleFont) }
            .keyboardShortcut(.tab, modifiers: .option)
          Button("Next font") { action(.nextFont) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
          Button("Previous font") { action(.previousFont) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        }
        if state.hasMenu {
          Button("Quick settings", systemImage: "slider.horizontal.3") { action(.settings) }
            .accessibilityIdentifier("review.settings")
        }
      } label: {
        toolLabel("Review tools", systemImage: "ellipsis")
      }.accessibilityIdentifier("review.tools")
    }.labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.large)
      .frame(minHeight: 44)
  }

  private func toolLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label(title, systemImage: systemImage).font(.system(size: 20))
      .frame(minWidth: 44, minHeight: 44)
  }

  private var compactProgress: some View {
    let count = "\(state.completed)/\(state.completed + state.remaining)"
    let status = "\(state.completed) completed, \(state.remaining) remaining"
    let spoken = state.accuracy.map { "Accuracy \($0), \(status)" } ?? status
    return ViewThatFits(in: .horizontal) {
      if let accuracy = state.accuracy {
        Text("\(Image(systemName: "hand.thumbsup")) \(accuracy) · \(count)")
          .fixedSize().accessibilityLabel(spoken).accessibilityIdentifier("review.progress")
      }
      Text(count).fixedSize().accessibilityLabel(spoken).accessibilityIdentifier("review.progress")
    }.font(.caption).monospacedDigit()
  }

  private var submitTitle: String {
    if state.phase == .incorrect { return "Continue" }
    if state.isAnki { return "Show answer" }
    return state.canSkip && state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Skip" : "Check answer"
  }

  private func question(compact: Bool = false, inline: Bool = false) -> some View {
    let prompt = [state.subjectType, state.prompt].filter { !$0.isEmpty }.joined(separator: " ")
    let layout = inline ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    return layout {
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
        .frame(
          maxWidth: .infinity, minHeight: 44, maxHeight: state.phase == .details ? 70 : .infinity
        )
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
      }.padding(.horizontal, 16).padding(.vertical, 4).foregroundStyle(.white).tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(state.subjectColor)
      Text(compact ? state.prompt : prompt)
        .font(compact ? .caption : .subheadline).fontWeight(.semibold)
        .multilineTextAlignment(.center).fixedSize(horizontal: inline, vertical: true)
        .accessibilityLabel(prompt)
        .accessibilityIdentifier("review.prompt")
        .padding(.horizontal, 8).padding(.vertical, compact ? 0 : 4)
        .frame(maxWidth: inline ? nil : .infinity)
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
