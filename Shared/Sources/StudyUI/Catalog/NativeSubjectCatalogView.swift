import StudyCore
import StudyPersistence
import SwiftUI

public struct NativeSubjectCatalogView: View {
  @Environment(\.studyICloudPreferences) private var iCloud
  @Environment(StudySubjectSettings.self) private var subjectSettings
  @Environment(\.dismiss) private var dismiss
  private let store: StudyStore
  private let accountID: String
  private let maximumLevel: Int
  private let initialQuery: SubjectCatalogQuery
  private let mode: SubjectCatalogView.Mode
  private let title: String
  @State private var level: Int
  @State private var collection = SubjectCatalogCollection(items: [])
  @State private var loaded = false
  @State private var error: String?
  @State private var selectedSubject: Int64?
  @AppStorage("catalog.showAnswers") private var showAnswers = true

  public init(
    store: StudyStore, accountID: String, maximumLevel: Int,
    initialQuery: SubjectCatalogQuery = .init(), mode: SubjectCatalogView.Mode = .all,
    title: String = "Subjects"
  ) {
    self.store = store
    self.accountID = accountID
    self.maximumLevel = maximumLevel
    self.initialQuery = initialQuery
    self.mode = mode
    self.title = title
    _level = State(initialValue: initialQuery.level)
  }
  private var back: (() -> Void)? {
    switch mode {
    case .level, .remaining: return { dismiss() }
    default: return nil
    }
  }
  public var body: some View {
    SubjectCatalogView(
      collection: collection, title: title, mode: mode,
      showAnswers: $showAnswers.syncing(.showCatalogAnswers, with: iCloud),
      maximumLevel: maximumLevel,
      selectedLevel: (mode == .level || mode == .remaining) ? $level : nil,
      preferences: {
        var value = subjectSettings.value
        value.primaryKanjiReadingsOnly = true
        return value
      }(), initialQuery: initialQuery, back: back, openSubject: { selectedSubject = $0 }
    ).overlay {
      if let error {
        ContentUnavailableView(
          "Catalog unavailable", systemImage: "book.closed", description: Text(error)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
      } else if !loaded {
        ProgressView("Loading saved catalog")
      }
    }.task(id: subjectSettings.value.showPreviousLevelGraph) {
      for await _ in await store.changes() {
        error = nil
        do {
          let value = try await store.subjectCatalog(accountID: accountID)
          try Task.checkCancellation()
          collection =
            mode == .remaining
            ? SubjectCatalogCollection(
              items: value.items.filter {
                ($0.status.stage?.rawValue ?? 0) < 5
                  && (subjectSettings.value.showPreviousLevelGraph
                    || $0.subject.kind != .vocabulary)
              },
              pendingCount: value.pendingCount,
              requiresAssignmentRefresh: value.requiresAssignmentRefresh) : value
          loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
    }.navigationDestination(item: $selectedSubject) { id in
      NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id).navigationTitle(
        "Subject")
    }
  }
}
