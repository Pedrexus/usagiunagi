// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyCore
import StudyUI
import SwiftUI
import WaniKaniAPI

final class MainWaniKaniTabViewController: UIHostingController<HomeDashboardView?> {
  protocol Delegate: AnyObject { func didPullToRefresh() }
  var services: TKMServices!
  weak var delegate: Delegate?
  var selectedSubjectCatalogLevel = -1
  var selectedSrsStageCategory = SRSStageCategory.apprentice
  var hasLessons = false
  var hasReviews = false
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices, delegate: Delegate?) {
    self.services = services
    self.delegate = delegate
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    update()
  }
  func update() {
    guard let user = services?.localCachingClient?.getUserInfo() else { return }
    let client = services.localCachingClient!
    var data = HomeDashboardData()
    data.onVacation = user.hasVacationStartedAt
    data.lessons = client.availableLessonCount
    data.reviews = client.availableReviewCount
    data.recentLessons = client.recentLessonCount
    data.recentMistakes = client.getRecentMistakesCount()
    data.leeches = client.leechCount
    let apprentice = client.apprenticeCount
    data.apprenticePractice = max(0, apprentice - data.recentLessons)
    data.lessonsDisabledMessage =
      apprentice >= Settings.apprenticeLessonsLimit ? "Apprentice limit reached" : nil
    hasLessons = !data.onVacation && data.lessons > 0 && data.lessonsDisabledMessage == nil
    hasReviews = !data.onVacation && data.reviews > 0
    data.hourlyReviews = [data.reviews] + client.upcomingReviews.prefix(24)
    let level = Int(user.currentLevel)
    let assignments = client.getAssignmentsAtUsersCurrentLevel()
    if Settings.showPreviousLevelGraph && level > 1 && !client.hasCompletedPreviousLevel() {
      data.levels.append(
        .init(number: level - 1, legacyAssignments: client.getAssignments(level: level - 1)))
    }
    data.levels.append(.init(number: level, legacyAssignments: assignments))
    data.timing = HomeTiming.rows(
      services: services, assignments: assignments,
      showMinutes: Settings.showMinutesForNextLevelUpReview)
    let counts = client.srsCategoryCounts
    data.stageCounts = (0..<5).map { counts.indices.contains($0) ? Int(counts[$0]) : 0 }
    data.excluded = Settings.allowExcludeItems ? client.excludedCount() : 0
    rootView = HomeDashboardView(
      data: data, action: { [weak self] in self?.perform($0) },
      refresh: { [weak self] in self?.delegate?.didPullToRefresh() })
  }
  private func perform(_ action: HomeAction) {
    switch action {
    case .reviews: startReviews()
    case .lessons: startLessons()
    case .chooseLessons: showLessonPicker()
    case .apprenticePractice: startAlreadyPassedApprenticeReviews()
    case .recentLessons: startRecentLessonReviews()
    case .recentMistakes: startRecentMistakeReviews()
    case .leeches: startAllLeechReviews()
    case .burned: startBurnedItemReviews()
    case .forecast: showTableForecast()
    case .excluded: perform(segue: StoryboardSegue.Main.showExcluded, sender: self)
    case .catalog(let level):
      selectedSubjectCatalogLevel = level
      perform(segue: StoryboardSegue.Main.showAll, sender: self)
    case .remaining(let level):
      selectedSubjectCatalogLevel = level
      perform(segue: StoryboardSegue.Main.showRemaining, sender: self)
    case .stage(let index):
      guard let category = SRSStageCategory(rawValue: index) else { return }
      selectedSrsStageCategory = category
      perform(segue: StoryboardSegue.Main.viewItemsInSrsCategory, sender: self)
    }
  }

  private func selectReviews(items: [ReviewItem]) -> [ReviewItem] {
    let policy = ReviewPreferencesAdapter.currentPolicy
    let hour = floor(Date().timeIntervalSince1970 / 3600) * 3600
    var generator = SystemRandomNumberGenerator()
    return policy.select(items, using: &generator) { item in
      let assignment = item.assignment
      var ratio = 0.0
      if policy.order == .longestRelativeWait,
        let subject = services.localCachingClient.getSubject(id: assignment.subjectID)
      {
        let interval = assignment.srsStage.duration(subject)
        if interval > 0 { ratio = (hour - Double(assignment.availableAt)) / interval }
      }
      return StudyReviewSortKey(
        stage: Int(assignment.srsStageNumber), level: Int(assignment.level),
        kind: assignment.subjectType == .radical
          ? .radical : assignment.subjectType == .kanji ? .kanji : .vocabulary,
        availableAt: Int64(assignment.availableAt), relativeWait: ratio)
    }
  }

  // MARK: - UIViewController

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    switch StoryboardSegue.Main(segue) {
    case .startReviews, .startRecentMistakeReviews, .startRecentLessonReviews,
      .startAlreadyPassedApprenticeReviews, .startAllLeechReviews, .startBurnedItemReviews:
      let client = services.localCachingClient!
      let route = StoryboardSegue.Main(segue)
      var items: [ReviewItem]
      switch route {
      case .startReviews:
        items = selectReviews(
          items: ReviewItem.readyForReview(
            assignments: client.getNonExcludedAssignments(), localCachingClient: client))
      case .startRecentMistakeReviews:
        items = ReviewItem.readyForRecentReview(
          assignments: client.getAllRecentMistakeAssignments(), localCachingClient: client)
      case .startRecentLessonReviews:
        items = ReviewItem.readyForRecentReview(
          assignments: client.getAllRecentLessonAssignments(), localCachingClient: client)
      case .startAlreadyPassedApprenticeReviews:
        items = ReviewItem.readyForAlreadyPassedApprenticeReview(
          assignments: client.getAssignmentsInCategory(category: .apprentice),
          localCachingClient: client)
      case .startAllLeechReviews:
        items = ReviewItem.readyForLeechReview(
          assignments: client.getAllLeeches(), localCachingClient: client)
      case .startBurnedItemReviews:
        items = ReviewItem.readyForBurnedReview(
          assignments: client.getAllBurnedAssignments(), localCachingClient: client)
      default: return
      }
      guard !items.isEmpty else { return }
      let practice = route != .startReviews
      if practice { items.shuffle() }
      let controller = segue.destination as! ReviewContainerViewController
      controller.setup(services: services, items: items, isPracticeSession: practice)

    case .startLessons:
      let assignments = services.localCachingClient.getNonExcludedAssignments()
      var items = ReviewItem.readyForLessons(
        assignments: assignments,
        localCachingClient: services.localCachingClient
      )
      .shuffled()
      if items.count == 0 {
        return
      }

      let preferences = services.lessonSettings.value
      items.sort { preferences.precedes($0.lessonSortKey, $1.lessonSortKey) }
      if items.count > preferences.batchSize {
        items = Array(items.prefix(preferences.batchSize))
      }

      let vc = segue.destination as! LessonsViewController
      vc.setup(services: services, items: items)

    case .showLessonPicker:
      let vc = segue.destination as! LessonPickerViewController
      vc.setup(services: services)

    case .showAll:
      let vc = segue.destination as! SubjectCatalogueViewController
      vc.setup(services: services, level: selectedSubjectCatalogLevel)

    case .showRemaining:
      let vc = segue.destination as! SubjectsRemainingViewController
      vc.setup(services: services, level: selectedSubjectCatalogLevel)

    case .showExcluded:
      let vc = segue.destination as! SubjectsExcludedViewController
      vc.setup(
        services: services, category: selectedSrsStageCategory,
        showAnswers: Settings.subjectCatalogueViewShowAnswers)

    case .tableForecast:
      let vc = segue.destination as! UpcomingReviewsViewController
      vc.setup(services: services)

    case .viewItemsInSrsCategory:
      let vc = segue.destination as! SubjectsByCategoryViewController
      vc.setup(
        services: services, category: selectedSrsStageCategory,
        showAnswers: Settings.subjectCatalogueViewShowAnswers)

    default:
      break
    }
  }

  // MARK: - Keyboard navigation

  override var keyCommands: [UIKeyCommand]? {
    var ret = [UIKeyCommand]()

    // Press return to keep studying, first lessons then reviews
    if hasLessons, !hasReviews {
      ret.append(
        UIKeyCommand(
          input: "\r",
          modifierFlags: [],
          action: #selector(startLessons),
          discoverabilityTitle: "Continue lessons"))
    } else if hasReviews {
      ret.append(
        UIKeyCommand(
          input: "\r",
          modifierFlags: [],
          action: #selector(startReviews),
          discoverabilityTitle: "Continue reviews"))
    }

    // Command L to start lessons, if any
    if hasLessons {
      ret.append(
        UIKeyCommand(
          input: "l",
          modifierFlags: [.command],
          action: #selector(startLessons),
          discoverabilityTitle: "Start lessons"))
    }

    // Command R to start reviews, if any
    if hasReviews {
      ret.append(
        UIKeyCommand(
          input: "r",
          modifierFlags: [.command],
          action: #selector(startReviews),
          discoverabilityTitle: "Start reviews"))
    }

    return ret
  }

  @objc func startReviews() {
    perform(segue: StoryboardSegue.Main.startReviews, sender: self)
  }

  @objc func startLessons() {
    perform(segue: StoryboardSegue.Main.startLessons, sender: self)
  }

  @objc func showLessonPicker() {
    perform(segue: StoryboardSegue.Main.showLessonPicker, sender: self)
  }

  @objc func showTableForecast() {
    perform(segue: StoryboardSegue.Main.tableForecast, sender: self)
  }

  @objc func startRecentMistakeReviews() {
    perform(segue: StoryboardSegue.Main.startRecentMistakeReviews, sender: self)
  }

  @objc func startRecentLessonReviews() {
    perform(segue: StoryboardSegue.Main.startRecentLessonReviews, sender: self)
  }

  @objc func startAlreadyPassedApprenticeReviews() {
    perform(segue: StoryboardSegue.Main.startAlreadyPassedApprenticeReviews, sender: self)
  }

  @objc func startAllLeechReviews() {
    perform(segue: StoryboardSegue.Main.startAllLeechReviews, sender: self)
  }

  @objc func startBurnedItemReviews() {
    perform(segue: StoryboardSegue.Main.startBurnedItemReviews, sender: self)
  }
}
