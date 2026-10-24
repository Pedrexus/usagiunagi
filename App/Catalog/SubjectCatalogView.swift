import StudyCore
import SwiftUI

/// All screens share native rows, search and answer concealment; hosts supply saved values/actions.
public struct SubjectCatalogView: View {
  public enum Mode { case level, remaining, stage, excluded, search, all }
  private let collection: SubjectCatalogCollection
  private let title: String
  private let mode: Mode
  private let maximumLevel: Int
  private let selectedLevel: Binding<Int>?
  private let preferences: SubjectDetailsPreferences
  private let back: (() -> Void)?
  private let openSubject: (Int64) -> Void
  @Binding private var showAnswers: Bool
  @State private var query = SubjectCatalogQuery()
  @State private var searching: Bool
  @State private var results: [SubjectCatalogItem]?
  @State private var error: String?
  private struct Request: Hashable {
    let collection: UUID
    let query: SubjectCatalogQuery
  }

  public init(
    collection: SubjectCatalogCollection, title: String, mode: Mode,
    showAnswers: Binding<Bool>, maximumLevel: Int = 60, selectedLevel: Binding<Int>? = nil,
    preferences: SubjectDetailsPreferences = .init(),
    initialQuery: SubjectCatalogQuery = .init(),
    back: (() -> Void)? = nil,
    openSubject: @escaping (Int64) -> Void
  ) {
    self._query = State(initialValue: initialQuery)
    self.collection = collection
    self.title = title
    self.mode = mode
    self._showAnswers = showAnswers
    self.maximumLevel = max(0, maximumLevel)
    self.selectedLevel = selectedLevel
    self.preferences = preferences
    self.back = back
    self.openSubject = openSubject
    self._searching = State(initialValue: mode == .search)
  }
  private var order: SubjectCatalogOrder {
    switch mode {
    case .remaining: .remaining
    case .stage: .stage
    default: .level
    }
  }
  private var hasQuery: Bool { !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  public var body: some View {
    List {
      if let selectedLevel, maximumLevel > 0 {
        Section {
          HStack {
            Button("Previous level", systemImage: "chevron.left") {
              selectedLevel.wrappedValue -= 1
            }
            .labelStyle(.iconOnly).disabled(selectedLevel.wrappedValue <= 1)
            .accessibilityIdentifier("catalog.previousLevel")
            Picker("Level", selection: selectedLevel) {
              ForEach(1...maximumLevel, id: \.self) { Text("Level \($0)").tag($0) }
            }.pickerStyle(.menu).frame(maxWidth: .infinity)
              .accessibilityIdentifier("catalog.level")
            Button("Next level", systemImage: "chevron.right") { selectedLevel.wrappedValue += 1 }
              .labelStyle(.iconOnly).disabled(selectedLevel.wrappedValue >= maximumLevel)
              .accessibilityIdentifier("catalog.nextLevel")
          }.buttonStyle(.bordered)
        }
      }
      if mode != .search || hasQuery, let results, !results.isEmpty {
        if hasQuery {
          Section("\(results.count) results") { rows(results) }
        } else {
          ForEach([SubjectKind.radical, .kanji, .vocabulary], id: \.rawValue) { kind in
            let items = results.filter { $0.subject.kind == kind }
            if !items.isEmpty {
              Section {
                rows(order.sorted(items, now: .now))
              } header: {
                HStack {
                  Text(kind == .radical ? "Radicals" : kind == .kanji ? "Kanji" : "Vocabulary")
                  Spacer()
                  Text(detail(items)).font(.caption).monospacedDigit()
                }
              }
            }
          }
        }
      }
    }
    .listStyle(.inset).id(collection.id)
    .accessibilityIdentifier("catalog.list")
    .scrollDismissesKeyboard(.interactively)
    .highPriorityGesture(
      DragGesture(minimumDistance: 60).onEnded { value in
        guard let selectedLevel, maximumLevel > 0,
          abs(value.translation.width) > abs(value.translation.height) * 2
        else { return }
        selectedLevel.wrappedValue = min(
          maximumLevel, max(1, selectedLevel.wrappedValue + (value.translation.width < 0 ? 1 : -1)))
      }, including: selectedLevel == nil ? .subviews : .all
    )
    .safeAreaInset(edge: .bottom) {
      if collection.requiresAssignmentRefresh {
        Label(
          "Refresh WaniKani to reload progress. Saved subjects remain available.",
          systemImage: "arrow.clockwise"
        )
        .font(.callout).padding().frame(maxWidth: .infinity).background(.bar)
      } else if collection.pendingCount > 0 {
        Label(
          "\(collection.pendingCount) uploads pending. Progress updates after syncing.",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption).padding().frame(maxWidth: .infinity).background(.bar)
      }
    }
    .overlay {
      Group {
        if mode == .search && !hasQuery {
          ContentUnavailableView(
            "Search saved subjects", systemImage: "magnifyingglass",
            description: Text("Search Japanese, meanings or readings. Romaji is supported."))
        } else if let error {
          ContentUnavailableView(
            "Search unavailable", systemImage: "magnifyingglass", description: Text(error))
        } else if results == nil {
          ProgressView("Loading saved subjects")
        } else if results?.isEmpty == true {
          ContentUnavailableView(
            "No matching subjects", systemImage: "character.book.closed",
            description: Text(
              hasQuery
                ? "Try another meaning or reading." : "There are no saved items in this selection.")
          )
        }
      }.allowsHitTesting(false)
    }
    .navigationTitle(mode == .level ? "Level \(query.level)" : title)
    .navigationBarBackButtonHidden(back != nil)
    .toolbarTitleDisplayMode(.inline)
    .searchable(
      text: $query.text, isPresented: $searching, prompt: "Japanese, meaning or reading"
    )
    .searchPresentationToolbarBehavior(.avoidHidingContent)
    .toolbar {
      if let back {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            mode == .search ? "Cancel" : "Back",
            systemImage: mode == .search ? "xmark" : "chevron.backward"
          ) {
            searching = false
            back()
          }
          .accessibilityIdentifier("catalog.back")
        }
      }
      if mode != .search {
        ToolbarItem(placement: .primaryAction) {
          Button(
            showAnswers ? "Hide answers" : "Show answers",
            systemImage: showAnswers ? "eye" : "eye.slash"
          ) { showAnswers.toggle() }
          .accessibilityIdentifier("catalog.answers")
          .accessibilityValue(showAnswers ? "Shown" : "Hidden")
        }
      }
      if mode == .all {
        ToolbarItem(placement: .primaryAction) {
          Menu("Filter subjects", systemImage: "line.3.horizontal.decrease") {
            Picker("Subject type", selection: $query.kind) {
              Text("All types").tag(SubjectKind?.none)
              Text("Radicals").tag(SubjectKind?.some(.radical))
              Text("Kanji").tag(SubjectKind?.some(.kanji))
              Text("Vocabulary").tag(SubjectKind?.some(.vocabulary))
            }
            Picker("Level", selection: $query.level) {
              Text("All levels").tag(0)
              if maximumLevel > 0 {
                ForEach(1...maximumLevel, id: \.self) { Text("Level \($0)").tag($0) }
              }
            }
            Picker("Study progress", selection: $query.scope) {
              ForEach(SubjectCatalogScope.allCases) { Text($0.rawValue).tag($0) }
            }
          }.accessibilityIdentifier("catalog.filters")
        }
      }
    }
    .onChange(of: selectedLevel?.wrappedValue) { _, level in if let level { query.level = level } }
    .task(id: Request(collection: collection.id, query: query)) {
      results = nil
      error = nil
      if mode == .search && !hasQuery {
        results = []
        return
      }
      do {
        let values = try await query.results(
          in: collection.items, limit: mode == .search ? 50 : nil)
        try Task.checkCancellation()
        results = values
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  private func detail(_ items: [SubjectCatalogItem]) -> String {
    if mode == .level {
      return
        "\(items.filter { ($0.status.stage?.rawValue ?? 0) >= 5 }.count) of \(items.count) at Guru+"
    }
    return mode == .remaining ? "\(items.count) left" : "\(items.count)"
  }
  private func rows(_ items: [SubjectCatalogItem]) -> some View {
    ForEach(items) { item in
      let row = SubjectCatalogRow(
        item: item, showAnswers: mode == .search || showAnswers, showsTiming: mode == .remaining,
        preferences: preferences)
      Button {
        openSubject(item.id)
      } label: {
        row
      }.buttonStyle(.plain).accessibilityLabel(row.accessibilityText)
        .accessibilityIdentifier("catalog.subject.\(item.id)")
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
  }
}

private struct SubjectCatalogRow: View {
  let item: SubjectCatalogItem
  let showAnswers: Bool
  let showsTiming: Bool
  let preferences: SubjectDetailsPreferences
  @Environment(\.dynamicTypeSize) private var typeSize
  private var subject: CatalogSubject { item.subject }
  private var meaning: String {
    subject.displayedMeanings(preferences: preferences).map(\.text).joined(separator: ", ")
  }
  private var readings: String {
    subject.kind == .radical
      ? "" : subject.displayedReadings(preferences: preferences).map(\.text).joined(separator: ", ")
  }
  var accessibilityText: String {
    [
      subject.japanese.isEmpty ? "Radical image" : subject.japanese,
      showAnswers ? meaning : "Answers hidden", showAnswers && !readings.isEmpty ? readings : nil,
      stageName, item.isExcluded ? "Excluded" : nil, showsTiming ? timingText : nil,
    ].compactMap { $0 }.joined(separator: ", ")
  }
  private var stageName: String {
    item.status.name.isEmpty ? "Level \(subject.level)" : item.status.name
  }
  private var symbol: String {
    switch item.status {
    case .locked: "lock.fill"
    case .lesson: "book"
    case .pending: "arrow.triangle.2.circlepath"
    case .unassigned: "number"
    case .studying(let stage, _, _):
      switch stage.rawValue {
      case 1...4: "leaf"
      case 5...6: "graduationcap"
      case 7: "seal"
      case 8: "sun.max"
      default: "flame.fill"
      }
    }
  }
  private var color: Color {
    if case .locked = item.status { return .gray }
    if item.status.stage == .burned { return Color(white: 0.2) }
    return StudyPalette.color(for: subject.kind)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        tile
        VStack(alignment: .leading, spacing: 4) {
          if showAnswers {
            Text(meaning).foregroundStyle(.primary)
            if !readings.isEmpty {
              Text(readings).font(.callout).foregroundStyle(.secondary)
            }
          } else {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 96, height: 12)
              .accessibilityLabel("Answers hidden")
          }
          if showsTiming, let timingText {
            Text(timingText).font(.caption).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !typeSize.isAccessibilitySize { badge }
      }
      if typeSize.isAccessibilitySize { badge }
    }.padding(.vertical, 4).contentShape(Rectangle())
  }
  private var badge: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Label(stageName, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
      if item.isExcluded {
        Label("Excluded", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var tile: some View {
    Group {
      if !subject.japanese.isEmpty {
        Text(subject.japanese).font(.title3)
      } else if let url = URL(string: subject.characterImageURL), !subject.characterImageURL.isEmpty
      {
        RadicalImageView(url: url).environment(\.colorScheme, .dark).frame(width: 32, height: 32)
      } else {
        Image(systemName: "square.dashed")
      }
    }.foregroundStyle(.white).padding(8).frame(minWidth: 44, minHeight: 44)
      .background(color, in: RoundedRectangle(cornerRadius: 10))
  }
  private var timingText: String? {
    switch item.status {
    case .locked:
      return subject.kind == .kanji
        ? "After its radicals" : subject.kind == .vocabulary ? "After its kanji" : "Locked"
    case .lesson: return "Available now"
    case .studying(_, let reviewAt, let guruAt):
      if let reviewAt, reviewAt <= .now { return "Review now" }
      if let guruAt, guruAt > .now {
        return
          "Guru in ~\(Duration.seconds(Date.now.distance(to: guruAt)).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))"
      }
      return nil
    case .pending: return "Waiting for sync"
    case .unassigned: return nil
    }
  }
}
