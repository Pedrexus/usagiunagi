// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import StudyCore
import StudySpeech
import StudyUI
import SwiftUI
import WaniKaniAPI

private let kDotColorApprentice = TKMStyle.color(forSRSStageCategory: .apprentice)
private let kDotColorGuru = TKMStyle.color(forSRSStageCategory: .guru)
private let kDotColorMaster = TKMStyle.color(forSRSStageCategory: .master)
private let kDotColorEnlightened = TKMStyle.color(forSRSStageCategory: .enlightened)
private let kDotColorBurned = TKMStyle.color(forSRSStageCategory: .burned)

private func getDots(stage: SRSStage) -> NSAttributedString? {
  var string: NSMutableAttributedString?
  switch stage {
  case .apprentice1:
    string = NSMutableAttributedString(string: "•◦◦◦",
                                       attributes: [.foregroundColor: kDotColorApprentice])
  case .apprentice2:
    string = NSMutableAttributedString(string: "••◦◦",
                                       attributes: [.foregroundColor: kDotColorApprentice])
  case .apprentice3:
    string = NSMutableAttributedString(string: "•••◦",
                                       attributes: [.foregroundColor: kDotColorApprentice])
  case .apprentice4:
    string = NSMutableAttributedString(string: "••••◦",
                                       attributes: [.foregroundColor: kDotColorApprentice])
    string?
      .addAttribute(.foregroundColor, value: kDotColorGuru, range: NSRange(location: 4, length: 1))
  case .guru1:
    string = NSMutableAttributedString(string: "•◦", attributes: [.foregroundColor: kDotColorGuru])
  case .guru2:
    string = NSMutableAttributedString(string: "••◦", attributes: [.foregroundColor: kDotColorGuru])
    string?
      .addAttribute(.foregroundColor, value: kDotColorMaster,
                    range: NSRange(location: 2, length: 1))
  case .master:
    string = NSMutableAttributedString(string: "•◦",
                                       attributes: [.foregroundColor: kDotColorMaster])
    string?
      .addAttribute(.foregroundColor, value: kDotColorEnlightened,
                    range: NSRange(location: 1, length: 1))
  case .enlightened:
    string = NSMutableAttributedString(string: "•◦",
                                       attributes: [.foregroundColor: kDotColorEnlightened])
    string?
      .addAttribute(.foregroundColor, value: kDotColorBurned,
                    range: NSRange(location: 1, length: 1))
  case .burned:
    string = NSMutableAttributedString(string: "•", attributes: [.foregroundColor: kDotColorBurned])
  default:
    string = nil
  }
  return string
}

@objc
protocol ReviewViewControllerDelegate: AnyObject {
  func allowsCheats(forReviewItem item: ReviewItem) -> Bool
  func allowsCustomFonts() -> Bool
  func showsSuccessRate() -> Bool
  func finishedAllReviewItems(_ reviewViewController: ReviewViewController)

  @objc optional func tappedMenuButton(reviewViewController: ReviewViewController,
                                       menuButton: UIView)
}

/// Compatibility host for navigation, legacy repository and rich subject details.
/// Layout and review controls live in the shared SwiftUI ReviewScreen.
class ReviewViewController: UIViewController, UITextFieldDelegate, SubjectDelegate {
  private let screen = ReviewScreenState()
  private let answerField = AnswerTextField(frame: .zero)
  private lazy var subjectDetails = LegacySubjectDetailsModel(services: services, delegate: self)
  private var kanaInput: TKMKanaInput!
  private var services: TKMServices!
  private weak var delegate: ReviewViewControllerDelegate!
  private var session: ReviewSession!
  private var showSubjectHistory = false
  private var previousSubject: TKMSubject?
  private var currentFontName = TKMStyle.japaneseFontName
  private var availableFonts: [String]?

  private var isAnkiModeActiveForCurrentTask: Bool {
    guard Settings.ankiMode else { return false }
    switch Settings.ankiModeTaskType {
    case .both: return true
    case .readingOnly: return session.activeTaskType == .reading
    case .meaningOnly: return session.activeTaskType == .meaning
    }
  }

  private var combinesAnkiQuestions: Bool {
    isAnkiModeActiveForCurrentTask && Settings.ankiModeCombineReadingMeaning && Settings
      .ankiModeTaskType == .both
  }

  func setup(services: TKMServices, items: [ReviewItem], showMenuButton: Bool,
             showSubjectHistory: Bool, delegate: ReviewViewControllerDelegate,
             isPracticeSession: Bool = false) {
    self.services = services
    self.delegate = delegate
    self.showSubjectHistory = showSubjectHistory
    screen.hasMenu = showMenuButton
    session = ReviewSession(repository: ReviewRepository(client: services.localCachingClient),
                            items: items, isPracticeSession: isPracticeSession)
  }

  var activeQueueLength: Int { session.activeQueueLength }
  var canWrapUp: Bool { session.canWrapUp }
  var tasksAnsweredCorrectly: Int { session.tasksAnsweredCorrectly }
  @objc var wrappingUp: Bool {
    get { session.wrappingUp }
    set {
      saveDetails()
      session.wrappingUp = newValue
      if newValue { randomTask() } else { updateProgress() }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    kanaInput = TKMKanaInput(delegate: self)
    answerField.delegate = kanaInput
    answerField.borderStyle = .roundedRect
    answerField.font = .preferredFont(forTextStyle: .title3)
    answerField.adjustsFontForContentSizeCategory = true
    answerField.textAlignment = .center
    answerField.autocapitalizationType = .none
    answerField.autocorrectionType = .no
    answerField.spellCheckingType = .no
    answerField.returnKeyType = .go
    answerField.accessibilityIdentifier = "review.answer"
    answerField.addAction(UIAction { [weak self] _ in self?.answerChanged() }, for: .editingChanged)
    let field = answerField
    let details = subjectDetails
    let root = ReviewScreen(state: screen, action: { [weak self] in self?.handle($0) },
                            input: { ExistingReviewView(view: field) },
                            details: { SubjectDetailsPage(model: details) })
    let host = UIHostingController(rootView: root)
    addChild(host)
    view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: false)
    SiriShortcutHelper.shared.attachShortcutActivity(self, type: .reviews)
    if !session.hasStarted { randomTask() } else { quickSettingsChanged() }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    focusAnswerField()
  }

  override func viewWillDisappear(_ animated: Bool) {
    saveDetails()
    super.viewWillDisappear(animated)
  }

  @objc func focusAnswerField() {
    guard screen.phase == .answering, !screen.isAnki else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.screen.phase == .answering,
            self.presentedViewController == nil else { return }
      self.answerField.becomeFirstResponder()
    }
  }

  func prepareForSettings() {
    view.endEditing(true)
    saveDetails()
  }

  func quickSettingsChanged() {
    updateQuestion(focus: false, resetAnswer: false)
    if screen.phase == .details {
      saveDetails()
      updateAnswerDetails()
    }
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    switch StoryboardSegue.Review(segue) {
    case .reviewSummary:
      (segue.destination as! ReviewSummaryViewController).setup(services: services,
                                                                items: session.completedReviews)
    case .subjectDetails:
      (segue.destination as! SubjectDetailsViewController).setup(services: services,
                                                                 subject: sender as! TKMSubject)
    default: break
    }
  }

  @objc func endReviewSession() {
    saveDetails()
    if session.completedReviews
      .isEmpty { navigationController?.popToRootViewController(animated: true) }
    else { perform(segue: StoryboardSegue.Review.reviewSummary, sender: self) }
  }

  private func randomTask() {
    if let error = session.initializationError {
      let alert = UIAlertController(title: "Unable to start review", message: error,
                                    preferredStyle: .alert)
      alert
        .addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in
          self?.endReviewSession()
        })
      DispatchQueue.main.async { [weak self] in self?.present(alert, animated: true) }
      return
    }
    if session.activeQueueLength == 0 { delegate.finishedAllReviewItems(self)
      return
    }
    session.nextTask()
    updateQuestion()
  }

  private func updateProgress() {
    screen.completed = session.reviewsCompleted
    screen.remaining = session.activeQueueLength + session.reviewQueueLength
    screen.accuracy = delegate.showsSuccessRate() ? session.successRateText : nil
    screen.wrappingUp = session.wrappingUp
    screen.canWrapUp = session.canWrapUp
    screen.activeCount = session.activeQueueLength
  }

  private func updateQuestion(focus: Bool = true, resetAnswer: Bool = true) {
    guard let subject = session.activeSubject,
          let assignment = session.activeAssignment else { return }
    if resetAnswer {
      screen.phase = .answering
      screen.feedback = ""
      screen.answer = ""
      answerField.text = ""
      answerField.textColor = .label
      answerField.isEnabled = true
    }
    screen.isAnki = isAnkiModeActiveForCurrentTask
    screen.questionKind = session.activeTaskType
    screen.canSkip = Settings.allowSkippingReviews
    screen.canOverride = delegate.allowsCheats(forReviewItem: session.activeTask)
    screen.canExclude = subject.hasVocabulary && Settings.allowExcludeItems
    screen.canAddSynonym = session.activeTaskType == .meaning
    screen.canPlayAudio = subject.hasVocabulary && !subject.vocabulary.audio.isEmpty
    screen.canChangeFont = delegate.allowsCustomFonts() && !Settings.selectedFonts.isEmpty
    screen.question = subject.japanese
    screen.questionImage = nil
    if subject.hasRadical, subject.radical.hasCharacterImageFile_p,
       let image = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(subject.id)) {
      screen.questionImage = Image(uiImage: image).renderingMode(.template)
    }
    let type: String
    switch assignment.subjectType {
    case .radical: type = "Radical"
      screen.subjectColor = StudyPalette.radical
    case .kanji: type = "Kanji"
      screen.subjectColor = StudyPalette.kanji
    default: type = "Vocabulary"
      screen.subjectColor = StudyPalette.vocabulary
    }
    var task = session.activeTaskType == .reading ? "Reading" : subject
      .hasRadical ? "Name" : "Meaning"
    if !subject.hasRadical, combinesAnkiQuestions {
      task = Settings.meaningFirst ? "Meaning + Reading" : "Reading + Meaning"
    }
    screen.prompt = type + " " + task
    screen.level = assignment.level > 0 ? "Level \(assignment.level)" : ""
    screen.stageAccessibility = assignment.srsStage.description
    switch Settings.srsLevelIndicatorStyle {
    case .none: screen.stage = ""
    case .bubble: screen.stage = assignment.srsStage.description
    case .dots: screen.stage = getDots(stage: assignment.srsStage)?.string ?? ""
    }
    if resetAnswer || availableFonts != fontsThatCanRenderText(subject.japanese, exclude: nil)
      .sorted() {
      currentFontName = randomFont(thatCanRenderText: subject.japanese)
      screen.questionFont = screen.phase == .details ? TKMStyle.japaneseFontName : currentFontName
    }
    screen.questionSize = TKMStyle.reviewSubjectFontSize(baseSize: 64)
    kanaInput.enabled = session.activeTaskType == .reading
    if let reading = subject.primaryReadings.first {
      kanaInput.alphabet = reading.hasType && reading.type == .onyomi && Settings
        .useKatakanaForOnyomi ? .katakana : .hiragana
    } else { kanaInput.alphabet = .hiragana }
    answerField.placeholder = kanaInput.enabled ? "答え" : "Your answer"
    answerField.useJapaneseKeyboard = Settings.autoSwitchKeyboard && kanaInput.enabled
    updateProgress()
    if focus { focusAnswerField() }
  }

  private func handle(_ action: ReviewScreenAction) {
    switch action {
    case .end: endReviewSession()
    case .wrap: wrappingUp = true
    case .stopWrapping: wrappingUp = false
    case .settings: delegate.tappedMenuButton?(reviewViewController: self, menuButton: view)
    case .voice: showVoiceAnswer()
    case .submit: enterKeyPressed()
    case .reveal: revealAnswer()
    case .retry: backspaceKeyPressed()
    case .correct: markCorrect()
    case .incorrect: markIncorrect()
    case .deferQuestion: askAgain()
    case .exclude: exclude()
    case .synonym: addSynonym()
    case .previous: previousSubjectButtonPressed()
    case .toggleFont: toggleFont()
    case .nextFont: showNextCustomFont()
    case .previousFont: showPreviousCustomFont()
    case .showAll: showAllInformation()
    case .playAudio: playAudio()
    case .focus: focusAnswerField()
    }
  }

  private func saveDetails() {
    if screen.phase == .details {
      session.refreshStudyMaterials()
    }
  }

  private func answerChanged() { screen.answer = answerField.text ?? "" }
  func textField(_: UITextField, shouldChangeCharactersIn _: NSRange,
                 replacementString text: String) -> Bool {
    if screen.phase == .incorrect {
      if text.isEmpty { backspaceKeyPressed() }
      return false
    }
    DispatchQueue.main.async { [weak self] in self?.answerChanged() }
    return true
  }

  func textFieldShouldReturn(_: UITextField) -> Bool { enterKeyPressed()
    return false
  }

  @objc func enterKeyPressed() {
    if screen.phase == .details {
      if screen.isAnki {
        screen.showAssessment = true
      } else {
        saveDetails()
        randomTask()
      }
      return
    }
    if screen.phase == .incorrect {
      randomTask()
      return
    }
    if screen.isAnki {
      markAnswer(.Incorrect)
      return
    }
    let text = (answerField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      if Settings.allowSkippingReviews { askAgain() }
      return
    }
    submit()
  }

  @objc func backspaceKeyPressed() {
    guard screen.phase == .incorrect else { return }
    screen.phase = .answering
    screen.feedback = ""
    answerField.text = ""
    answerField.textColor = .label
    answerChanged()
    focusAnswerField()
  }

  private func submit() {
    answerField.text = AnswerChecker.normalizedString(answerField.text ?? "",
                                                      taskType: session.activeTaskType,
                                                      alphabet: kanaInput.alphabet)
    answerChanged()
    let result = AnswerChecker.checkAnswer(screen.answer, subject: session.activeSubject,
                                           studyMaterials: session.activeStudyMaterials,
                                           taskType: session.activeTaskType,
                                           localCachingClient: services.localCachingClient)
    switch result {
    case .precise: markAnswer(.Correct)
    case .imprecise:
      if Settings.exactMatch { screen.feedback = "Use the exact meaning." }
      else { markAnswer(.Correct) }
    case .incorrect: markAnswer(.Incorrect)
    case .otherKanjiReading: screen.feedback = "Use the reading taught for this kanji."
    case let .mismatchingOkurigana(ranges): highlight(ranges)
      screen.feedback = "Check the kana following the kanji."
    case let .containsInvalidCharacters(ranges): highlight(ranges)
      screen.feedback = "Check the highlighted characters."
    case .isReadingButWantMeaning: screen.feedback = "Enter the meaning. Your reading was correct."
      session.creditReading()
    }
  }

  private func highlight(_ ranges: [NSRange]) {
    let text = NSMutableAttributedString(string: screen.answer)
    for range in ranges {
      text.addAttribute(.foregroundColor, value: UIColor.systemRed, range: range)
    }
    answerField.attributedText = text
  }

  private func markAnswer(_ result: AnswerResult) {
    saveDetails()
    if result == .AskAgainLater { session.moveActiveTaskToEnd()
      randomTask()
      return
    }
    if result == .Exclude { session.excludeTask()
      randomTask()
      return
    }
    guard var marked = session.markAnswer(result) else { return }
    if result != .Incorrect {
      if !marked.subjectFinished, !session.activeSubject.hasRadical, combinesAnkiQuestions {
        session.nextTask(continuingCurrentItem: true)
        if let combined = session.markAnswer(.Correct) { marked = combined }
      }
      let subject = session.activeSubject!
      if Settings.playAudioAutomatically,
         session.activeTaskType == .reading || subject.readings.isEmpty,
         subject.hasVocabulary,
         !subject.vocabulary.audio.isEmpty { services.audio.play(subjectID: subject.id,
                                                                 delegate: nil)
      }
      if marked.subjectFinished, showSubjectHistory { previousSubject = subject
        screen.previous = subject.japanese
      }
      screen.successCount += 1
      randomTask()
    } else {
      updateProgress()
      answerField.textColor = .systemRed
      if Settings.showAnswerImmediately || screen.isAnki { revealAnswer() }
      else { screen.phase = .incorrect
        screen.feedback = "Incorrect answer"
      }
    }
  }

  private func updateAnswerDetails() {
    subjectDetails.update(subject: session.activeSubject, assignment: session.activeAssignment,
      task: Settings.showFullAnswer || combinesAnkiQuestions ? nil : session.activeTask,
      reviewQuestion: session.activeTaskType, material: session.activeStudyMaterials)
    screen.canShowAll = subjectDetails.questions != [.meaning, .reading]
  }

  @objc private func revealAnswer() {
    updateAnswerDetails()
    screen.phase = .details
    screen.questionFont = TKMStyle.japaneseFontName
    answerField.resignFirstResponder()
    becomeFirstResponder()
  }

  @objc func markCorrect() {
    guard screen.phase == .details, screen.canOverride || screen.isAnki else { return }
    markAnswer(.OverrideAnswerCorrect)
  }

  @objc func commandCPressed() {
    // Native SwiftUI selection handles Copy before this non-priority shortcut.
    markCorrect()
  }

  @objc func markIncorrect() { guard screen.phase == .details else { return }
    saveDetails()
    randomTask()
  }

  @objc func askAgain() { markAnswer(.AskAgainLater) }
  @objc func exclude() {
    guard screen.canExclude, screen.canOverride || screen.isAnki else { return }
    session.setExclude(true)
    markAnswer(.Exclude)
  }

  @objc func addSynonym() {
    guard screen.phase == .details, screen.canAddSynonym,
          screen.canOverride || screen.isAnki else { return }
    let alert = UIAlertController(title: "Add synonym",
                                  message: "Accept this meaning for future reviews.",
                                  preferredStyle: .alert)
    alert.addTextField { $0.text = self.screen.answer
      $0.autocapitalizationType = .none
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert
      .addAction(UIAlertAction(title: "Add and mark correct",
                               style: .default) { [weak self, weak alert] _ in
          guard let self,
                let text = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
          self.saveDetails()
          self.session.addSynonym(text)
          self.markCorrect()
        })
    present(alert, animated: true)
  }

  func didTapSubject(_ subject: TKMSubject) {
    saveDetails()
    perform(segue: StoryboardSegue.Review.subjectDetails, sender: subject)
  }

  @objc private func previousSubjectButtonPressed() {
    if let previousSubject { didTapSubject(previousSubject) }
  }

  func openPracticeReview(_ subject: TKMSubject) {
    guard FeatureFlags.showSubjectDeveloperOptions else { return }
    saveDetails()
    navigationController?.pushViewController(ReviewContainerViewController.practice(services: services, subject: subject), animated: true)
  }

  @objc func showAllInformation() {
    if screen.phase == .details { subjectDetails.showAllFields(); screen.canShowAll = false }
  }

  @objc func playAudio() { if screen.phase == .details { subjectDetails.playAudio() } }

  func fontsThatCanRenderText(_ text: String, exclude: [String]?) -> [String] {
    var availableFonts: [String] = []

    for filename in Settings.selectedFonts {
      if let font = services.fontLoader.font(fileName: filename) {
        if let ex = exclude, ex.contains(font.fontName) {
          continue
        }
        if font.canRender(text) {
          availableFonts.append(font.fontName)
        }
      }
    }

    return availableFonts
  }

  func nextCustomFont(thatCanRenderText _: String) -> String? {
    if let availableFonts = availableFonts,
       let index = availableFonts.firstIndex(of: currentFontName) {
      if index + 1 >= availableFonts.count {
        return availableFonts.first
      } else {
        return availableFonts[index + 1]
      }
    }
    return nil
  }

  func previousCustomFont(thatCanRenderText _: String) -> String? {
    if let availableFonts = availableFonts,
       let index = availableFonts.firstIndex(of: currentFontName) {
      if index == 0 {
        return availableFonts.last
      } else {
        return availableFonts[index - 1]
      }
    }
    return nil
  }

  func randomFont(thatCanRenderText text: String) -> String {
    if delegate.allowsCustomFonts() {
      // Re-set the supported fonts when we pick a random one as that is the first
      // step.
      availableFonts = fontsThatCanRenderText(text, exclude: nil).sorted()
      return availableFonts?.randomElement() ?? TKMStyle.japaneseFontName
    } else {
      return TKMStyle.japaneseFontName
    }
  }

  @objc func toggleFont() {
    guard screen.canChangeFont else { return }
    screen.questionFont = screen.questionFont == TKMStyle
      .japaneseFontName ? currentFontName : TKMStyle.japaneseFontName
  }

  @objc func showNextCustomFont() {
    guard screen.canChangeFont else { return }
    currentFontName = nextCustomFont(thatCanRenderText: screen.question) ?? TKMStyle
      .japaneseFontName
    screen.questionFont = currentFontName
  }

  @objc func showPreviousCustomFont() {
    guard screen.canChangeFont else { return }
    currentFontName = previousCustomFont(thatCanRenderText: screen.question) ?? TKMStyle
      .japaneseFontName
    screen.questionFont = currentFontName
  }

  private func showVoiceAnswer() {
    guard let token = session.questionToken, screen.phase == .answering,
          !screen.isAnki else { return }
    services.audio.stopPlayback()
    answerField.resignFirstResponder()
    var model = VoiceReviewController(question: token)
    #if DEBUG
      if Screenshotter.isActive, ProcessInfo.processInfo.arguments.contains("VoiceReviewFixture") {
        model = VoiceReviewController(question: token,
                                      capture: SampleVoiceCapture(transcript: token
                                        .kind == .meaning ? "Personally." : "私自身。"))
      }
    #endif
    let panel = VoiceAnswerPanel(model: model, submit: { [weak self] transcript in
      guard let self, self.session.questionToken == token else { return }
      self.dismiss(animated: true) {
        guard self.session.questionToken == token else { return }
        self.answerField.text = transcript
        self.answerChanged()
        self.submit()
      }
    }, cancel: { [weak self] in self?.dismiss(animated: true) { self?.focusAnswerField() } })
    let host = UIHostingController(rootView: panel)
    host.modalPresentationStyle = .formSheet
    present(host, animated: true)
  }

  override var canBecomeFirstResponder: Bool { true }
  override var keyCommands: [UIKeyCommand]? {
    var commands = [UIKeyCommand]()
    func add(_ input: String, _ flags: UIKeyModifierFlags = [], _ action: Selector,
             _ title: String) {
      commands.append(UIKeyCommand(input: input, modifierFlags: flags, action: action,
                                   discoverabilityTitle: title))
    }
    if screen.phase != .answering || screen.isAnki {
      add("\r", [], #selector(enterKeyPressed), "Continue")
      add("\u{3}", [], #selector(enterKeyPressed), "Continue")
    }
    if screen.phase == .incorrect {
      add("\u{8}", [], #selector(backspaceKeyPressed), "Clear wrong answer")
      add("f", [], #selector(revealAnswer), "Reveal answer")
    }
    if screen.phase == .details {
      add(" ", [], #selector(showAllInformation), "Show all information")
      add("j", [], #selector(playAudio), "Play reading")
      if screen.canOverride || screen.isAnki {
        add("a", .command, #selector(askAgain), "Ask again later")
        add("c", .command, #selector(commandCPressed), "Mark correct")
        add("c", .control, #selector(markCorrect), "Mark correct")
        add("i", .command, #selector(markIncorrect), "Mark incorrect")
        add("i", .control, #selector(markIncorrect), "Mark incorrect")
        if screen.canAddSynonym { add("s", .command, #selector(addSynonym), "Add synonym") }
      }
    }
    if screen.canChangeFont {
      add("\t", [], #selector(toggleFont), "Toggle font")
      add(UIKeyCommand.inputRightArrow, [], #selector(showNextCustomFont), "Next font")
      add(UIKeyCommand.inputLeftArrow, [], #selector(showPreviousCustomFont), "Previous font")
    }
    if previousSubject != nil { add("p", .command, #selector(previousSubjectButtonPressed),
                                    "Previous subject") }
    return commands
  }
}

private struct ExistingReviewView<V: UIView>: UIViewRepresentable {
  let view: V
  func makeUIView(context _: Context) -> V { view }
  func updateUIView(_: V, context _: Context) {}
}
