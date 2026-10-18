import StudyCore
import StudyPersistence
import SwiftUI

public struct NativeSubjectCatalogView: View {
  private let store: StudyStore
  private let accountID: String
  private let maximumLevel: Int
  @State private var collection = SubjectCatalogCollection(items: [])
  @State private var loaded = false
  @State private var error: String?
  @State private var selectedSubject: Int64?
  @AppStorage("catalog.showAnswers") private var showAnswers = true

  public init(store: StudyStore, accountID: String, maximumLevel: Int) {
    self.store = store
    self.accountID = accountID
    self.maximumLevel = maximumLevel
  }
  public var body: some View {
    NavigationStack {
      SubjectCatalogView(
        collection: collection, title: "Subjects", mode: .all,
        showAnswers: $showAnswers, maximumLevel: maximumLevel,
        preferences: {
          var value = SubjectDetailsPreferences()
          value.primaryKanjiReadingsOnly = true
          return value
        }(),
        openSubject: { selectedSubject = $0 }
      )
      .overlay {
        if let error {
          ContentUnavailableView(
            "Catalog unavailable", systemImage: "book.closed", description: Text(error)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        } else if !loaded {
          ProgressView("Loading saved catalog")
        }
      }
      .task {
        error = nil
        do {
          let value = try await store.subjectCatalog(accountID: accountID)
          try Task.checkCancellation()
          collection = value
          loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
      .navigationDestination(item: $selectedSubject) { id in
        NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id).navigationTitle(
          "Subject")
      }
    }
  }
}
