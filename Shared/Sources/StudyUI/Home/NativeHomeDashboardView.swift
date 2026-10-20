import Foundation
import StudyCore
import StudyPersistence
import SwiftUI

public enum StudyDestination: Hashable, Sendable {
  case reviews
  case lessons(automatic: Bool)
  case practice(StudyPracticeScope)
  case catalog(SubjectCatalogQuery, remaining: Bool = false)
  case subject(Int64)
  case search, forecast, katakana
  case reviewSettings, savedWork, account, fonts, offlineAudio, lessonSettings, subjectSettings,
    appearanceSettings, developerSettings
  init(resuming session: StudySession) {
    if let scope = session.practiceScope {
      self = .practice(scope)
    } else if session.items.values.first?.isLesson == true {
      self = .lessons(automatic: true)
    } else {
      self = .reviews
    }
  }
}

struct NativeHomeDashboardView: View {
  @AppStorage("native.showMinutesForNextLevelUpReview") private var showMinutes = false
  @StoredReviewPreferences private var reviewPreferences
  @Environment(StudyLessonSettings.self) private var lessonSettings
  @Environment(StudySubjectSettings.self) private var subjectSettings
  let model: StudyAppModel
  let active: Bool
  let route: (StudyDestination) -> Void
  @State private var data: HomeDashboardData?
  @State private var error: String?
  private struct Request: Hashable {
    let active: Bool
    let account: String?
    let revision: UUID
    let pending: Int?
    let date: Date
    let lessonPreferences: StudyLessonPreferences
    let policy: StudyReviewPolicy
    let showMinutes: Bool
    let showPreviousLevelGraph: Bool
  }
  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      content.task(
        id: Request(
          active: active, account: model.snapshot?.accountID,
          revision: model.dataRevision, pending: model.snapshot?.pendingReviews,
          date: context.date, lessonPreferences: lessonSettings.value,
          policy: reviewPreferences.policy, showMinutes: showMinutes,
          showPreviousLevelGraph: subjectSettings.value.showPreviousLevelGraph)
      ) {
        if active { await load() }
      }
    }
    .disabled(!active)
  }
  private var content: some View {

    Group {
      if let data {
        HomeDashboardView(
          data: data, action: open,
          refresh: {
            await model.refresh()
            await load()
          }, resume: { Task { await resume() } })
      } else if let error {
        ContentUnavailableView("Home unavailable", systemImage: "house", description: Text(error))
        Button("Try again") { Task { await load() } }
      } else {
        ProgressView("Loading saved study progress")
      }
    }
  }
  private func load() async {
    error = nil
    guard let snapshot = model.snapshot else { return }
    do {
      let value: HomeDashboardData
      if !snapshot.isSample, let accountID = snapshot.accountID, let store = model.savedWorkStore {
        value = try await store.homeData(
          accountID: accountID, lessonPreferences: lessonSettings.value,
          subjectPreferences: subjectSettings.value, policy: reviewPreferences.policy,
          showMinutes: showMinutes)
      } else {
        let available = Self.preview(snapshot)
        var preview = HomeDashboardData()
        preview.notice =
          snapshot.isSample
          ? "Sample data · browsing only" : "Saved statistics · connect to verify your account"
        preview.studyUnavailableMessage = "Connect your WaniKani account to study."
        preview.reviews = available.scheduled.count
        preview.stageCounts = available.stageCounts
        preview.hourlyReviews = available.hourlyReviews
        preview.levels = [
          .init(
            number: snapshot.currentLevel,
            progress: available.progress(level: snapshot.currentLevel))
        ]
        if snapshot.assignments.isEmpty {
          preview.progressUnavailableMessage = "This preview contains subjects, not study progress."
        }
        value = preview
      }
      try Task.checkCancellation()
      guard model.snapshot?.accountID == snapshot.accountID else { return }
      data = value
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
  static func preview(_ snapshot: StudySnapshot) -> StudyAvailability {
    var profile = StudyAccountProfile(username: snapshot.username)
    profile.level = snapshot.currentLevel
    profile.maxLevelGranted = 60
    let account = StudyAccountState(legacy: .init(schemaVersion: 15, profile: profile))
    let subjects = snapshot.subjects.map { value in
      var subject = CatalogSubject(id: value.id, kind: value.kind)
      subject.japanese = value.characters
      subject.level = value.level
      subject.meanings = [.init(value.meaning, role: .primary)]
      subject.readings = value.readings.map { .init($0, isPrimary: true, kind: .unknown) }
      subject.documentURL = value.documentURL?.absoluteString ?? ""
      return subject
    }
    let byID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let assignments = snapshot.assignments.compactMap { value -> CatalogAssignment? in
      guard let subject = byID[value.subjectID] else { return nil }
      var assignment = CatalogAssignment(
        id: value.subjectID, subjectID: value.subjectID, kind: subject.kind)
      assignment.level = subject.level
      assignment.srsStage = value.srsStageNumber
      assignment.availableAt = value.hasAvailableAt ? value.availableAt : nil
      assignment.startedAt = value.srsStageNumber > 0 ? 1 : nil
      return assignment
    }
    return .init(account: account, subjects: subjects, assignments: assignments)
  }
  private func open(_ action: HomeAction) {
    switch action {
    case .reviews: route(.reviews)
    case .lessons: route(.lessons(automatic: true))
    case .chooseLessons: route(.lessons(automatic: false))
    case .apprenticePractice: route(.practice(.apprentice))
    case .recentLessons: route(.practice(.recentLessons))
    case .recentMistakes: route(.practice(.recentMistakes))
    case .leeches: route(.practice(.leeches))
    case .burned: route(.practice(.burned))
    case .forecast: route(.forecast)
    case .catalog(let level):
      var query = SubjectCatalogQuery()
      query.level = level
      route(.catalog(query))
    case .remaining(let level):
      var query = SubjectCatalogQuery()
      query.level = level
      route(.catalog(query, remaining: true))
    case .stage(let index):
      guard let category = StudySRSCategory(rawValue: index) else { return }
      var query = SubjectCatalogQuery()
      query.scope = category.catalogScope
      route(.catalog(query))
    case .excluded:
      var query = SubjectCatalogQuery()
      query.scope = .excluded
      route(.catalog(query))
    }
  }
  private func resume() async {
    do {
      guard let accountID = model.snapshot?.accountID, let store = model.savedWorkStore,
        let session = try await store.session(accountID: accountID)?.session
      else {
        await load()
        return
      }
      route(StudyDestination(resuming: session))
    } catch { self.error = error.localizedDescription }
  }
}

struct NativeForecastView: View {
  @Environment(StudyLessonSettings.self) private var lessonSettings
  let model: StudyAppModel
  @State private var hours: [UpcomingReviewsView.Hour]?
  @State private var error: String?
  private struct Request: Hashable {
    let account: String?
    let savedAt: Date?
    let preferences: StudyLessonPreferences
  }
  var body: some View {
    Group {
      if let error {
        ContentUnavailableView(
          "Forecast unavailable", systemImage: "calendar", description: Text(error))
      } else if let hours {
        UpcomingReviewsView(hours: hours)
      } else {
        ProgressView("Loading saved forecast")
      }
    }.navigationTitle("Upcoming reviews").task(
      id: Request(
        account: model.snapshot?.accountID, savedAt: model.snapshot?.savedAt,
        preferences: lessonSettings.value)
    ) {
      do {
        guard let snapshot = model.snapshot else { return }
        guard !snapshot.requiresAssignmentRefresh, snapshot.pendingReviews == 0,
          !snapshot.onVacation
        else {
          error =
            snapshot.onVacation
            ? "Reviews are paused during vacation."
            : "Refresh and sync saved work to update the forecast."
          return
        }
        let available =
          if let accountID = snapshot.accountID, let store = model.savedWorkStore,
            !snapshot.isSample
          {
            try await store.availability(
              accountID: accountID, lessonPreferences: lessonSettings.value)
          } else { NativeHomeDashboardView.preview(snapshot) }
        let groups = Dictionary(grouping: available.scheduledFuture) { item in
          Int(
            ceil(max(0, Double(item.availableAt ?? 0) - available.now.timeIntervalSince1970) / 3600)
          )
        }
        var cumulative: [CatalogAssignment] = []
        let values: [UpcomingReviewsView.Hour] = Set(groups.keys).union([0]).sorted().map { hour in
          let new = groups[hour] ?? []
          cumulative += new
          return .init(
            id: hour, date: available.now.addingTimeInterval(Double(hour) * 3600),
            total: cumulative.count, newReviews: new.count,
            stages: StudySRSCategory.allCases.filter { $0 != .burned }.map { category in
              .init(
                category.name,
                cumulative.filter { StudySRSStage(rawValue: $0.srsStage)?.category == category }
                  .count)
            },
            subjects: [SubjectKind.radical, .kanji, .vocabulary].map { kind in
              .init(
                kind == .radical ? "Radicals" : kind == .kanji ? "Kanji" : "Vocabulary",
                cumulative.filter { $0.kind == kind }.count)
            })
        }
        try Task.checkCancellation()
        hours = values
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
}
