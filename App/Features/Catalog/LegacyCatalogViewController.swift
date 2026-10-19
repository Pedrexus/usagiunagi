// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Observation
import StudyCore
import StudyUI
import SwiftUI
import WaniKaniAPI

protocol SearchResultViewControllerDelegate: NSObject {
  func searchResultSelected(subject: TKMSubject)
}

/// Temporary cache/navigation boundary. All list, search and paging presentation is SwiftUI.
@MainActor @Observable final class LegacyCatalogModel {
  enum Source {
    case level, remaining
    case stage(SRSStageCategory)
    case excluded, search
  }
  private let services: TKMServices
  private let client: LocalCachingClient
  private let account: String?
  let source: Source
  var level: Int { didSet { if level != oldValue { reload() } } }
  var collection = SubjectCatalogCollection(items: [])
  var error: String?
  var showAnswers: Bool {
    didSet { Settings.subjectCatalogueViewShowAnswers = showAnswers }
  }
  init(services: TKMServices, source: Source, level: Int) {
    self.services = services
    self.client = services.localCachingClient
    self.account = services.localCachingClient.getUserInfo()?.username
    self.source = source
    self.level = level
    switch source {
    case .remaining, .excluded, .search: self.showAnswers = true
    default: self.showAnswers = Settings.subjectCatalogueViewShowAnswers
    }
  }
  var maximumLevel: Int { client.maxLevelGrantedBySubscription }
  var mode: SubjectCatalogView.Mode {
    switch source {
    case .level: .level
    case .remaining: .remaining
    case .stage: .stage
    case .excluded: .excluded
    case .search: .search
    }
  }
  var title: String {
    switch source {
    case .level: "Level \(level)"
    case .remaining: "Level \(level) · Remaining to Guru"
    case .stage(let category): category.description
    case .excluded: "Excluded items"
    case .search: "Search subjects"
    }
  }
  var preferences: SubjectDetailsPreferences {
    var result = services.subjectSettings.value
    result.primaryKanjiReadingsOnly = true
    return result
  }
  private func checkAccount() throws {
    guard services.localCachingClient === client, let account, !account.isEmpty,
      client.getUserInfo()?.username == account
    else { throw CatalogError.changedAccount }
  }
  func reload() {
    error = nil
    do {
      try checkAccount()
      let pending = client.getAllPendingProgress(limit: nil)
      let pendingIDs = Set(pending.map { $0.assignment.subjectID })
      let assignments: [TKMAssignment]
      let subjects: [TKMSubject]
      switch source {
      case .level, .remaining:
        guard (1...max(1, maximumLevel)).contains(level), maximumLevel > 0 else {
          throw CatalogError.unavailableLevel
        }
        assignments = client.getAssignments(level: level)
        subjects = assignments.compactMap { client.getSubject(id: $0.subjectID) }
      case .stage(let category):
        assignments = client.getAssignmentsInCategory(category: category).filter {
          $0.startedAt != 0
        }
        subjects = assignments.compactMap { client.getSubject(id: $0.subjectID) }
      case .excluded:
        assignments = client.getExcludedAssignments()
        subjects = assignments.compactMap { client.getSubject(id: $0.subjectID) }
      case .search:
        var byID = Dictionary(
          client.getAllAssignments().map { ($0.subjectID, $0) },
          uniquingKeysWith: { first, _ in first })
        for progress in pending
        where byID[progress.assignment.subjectID] == nil {
          byID[progress.assignment.subjectID] = progress.assignment
        }
        assignments = Array(byID.values)
        subjects = client.getAllSubjects()
      }
      let byID = Dictionary(
        assignments.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
      var items: [SubjectCatalogItem] = []
      var seen = Set<Int64>()
      for subject in subjects
      where subject.level <= maximumLevel && seen.insert(subject.id).inserted {
        let assignment = byID[subject.id]
        if case .remaining = source {
          guard let assignment, assignment.srsStage <= .apprentice4,
            Settings.showPreviousLevelGraph || subject.subjectType != .vocabulary
          else { continue }
        }
        let status: SubjectCatalogItem.Status
        if pendingIDs.contains(subject.id) {
          status = .pending
        } else if let assignment {
          if assignment.isLocked {
            status = .locked
          } else if assignment.isLessonStage {
            status = .lesson
          } else if let stage = StudySRSStage(rawValue: Int(assignment.srsStageNumber)) {
            status = .studying(
              stage, reviewAt: assignment.isReviewStage ? assignment.reviewDate : nil,
              guruAt: assignment.guruDate(subject: subject))
          } else {
            status = .unassigned
          }
        } else {
          status = .unassigned
        }
        let excluded: Bool
        if case .excluded = source { excluded = true } else { excluded = false }
        items.append(
          .init(
            subject: try LegacyStudyImporter.catalogSubject(subject), status: status,
            isExcluded: excluded))
      }
      try checkAccount()
      collection = SubjectCatalogCollection(items: items, pendingCount: pending.count)
    } catch {
      collection = SubjectCatalogCollection(items: [])
      self.error = error.localizedDescription
    }
  }
  func image(_ id: Int64) -> Image? {
    guard let value = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(id)) else {
      return nil
    }
    return Image(uiImage: value).renderingMode(.template)
  }
  private enum CatalogError: Error, LocalizedError {
    case changedAccount, unavailableLevel
    var errorDescription: String? {
      switch self {
      case .changedAccount: "The account changed. Close and reopen this catalog."
      case .unavailableLevel: "Refresh this account before browsing that level."
      }
    }
  }
}

struct LegacyCatalogScreen: View {
  @Bindable var model: LegacyCatalogModel
  let back: () -> Void
  let openSubject: (Int64) -> Void
  var body: some View {
    NavigationStack {
      SubjectCatalogView(
        collection: model.collection, title: model.title, mode: model.mode,
        showAnswers: $model.showAnswers, maximumLevel: model.maximumLevel,
        selectedLevel: model.mode == .level ? $model.level : nil,
        preferences: model.preferences, japaneseFont: TKMStyle.japaneseFontName,
        image: model.image, back: back, openSubject: openSubject
      )
      .overlay {
        if let error = model.error {
          ContentUnavailableView(
            "Catalog unavailable", systemImage: "book.closed", description: Text(error)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        }
      }
    }
  }
}

class LegacyCatalogViewController: UIHostingController<LegacyCatalogScreen?>, TKMViewController {
  private var services: TKMServices!
  private var model: LegacyCatalogModel!
  private weak var searchDelegate: SearchResultViewControllerDelegate?
  var canSwipeToGoBack: Bool { model.mode != .level }
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func configure(
    services: TKMServices, source: LegacyCatalogModel.Source, level: Int = 1,
    delegate: SearchResultViewControllerDelegate? = nil
  ) {
    self.services = services
    self.searchDelegate = delegate
    model = LegacyCatalogModel(services: services, source: source, level: level)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    rootView = LegacyCatalogScreen(
      model: model,
      back: { [weak self] in
        self?.navigationController?.popViewController(animated: true)
      },
      openSubject: { [weak self] id in
        guard let self, let subject = services.localCachingClient.getSubject(id: id) else { return }
        if let searchDelegate {
          searchDelegate.searchResultSelected(subject: subject)
        } else {
          let controller = StoryboardScene.SubjectDetails.initialScene.instantiate()
          controller.setup(services: services, subject: subject)
          navigationController?.pushViewController(controller, animated: true)
        }
      })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
    model.reload()
  }
}

final class SubjectCatalogueViewController: LegacyCatalogViewController {
  func setup(services: TKMServices, level: Int) {
    configure(services: services, source: .level, level: level)
  }
}
final class SubjectsRemainingViewController: LegacyCatalogViewController {
  func setup(services: TKMServices, level: Int) {
    configure(services: services, source: .remaining, level: level)
  }
}
final class SubjectsByCategoryViewController: LegacyCatalogViewController {
  func setup(services: TKMServices, category: SRSStageCategory, showAnswers _: Bool) {
    configure(services: services, source: .stage(category))
  }
}
final class SubjectsExcludedViewController: LegacyCatalogViewController {
  func setup(services: TKMServices, category _: SRSStageCategory, showAnswers _: Bool) {
    configure(services: services, source: .excluded)
  }
}
final class SearchResultViewController: LegacyCatalogViewController {
  func setup(services: TKMServices, delegate: SearchResultViewControllerDelegate) {
    configure(services: services, source: .search, delegate: delegate)
  }
}
