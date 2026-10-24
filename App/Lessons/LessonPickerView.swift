import StudyCore
import SwiftUI

/// The original level/type grid, with native selection and host-owned lesson validation.
struct LessonPickerView: View {
  let items: [CatalogSubject]
  var batchSize = 5
  var selection: Binding<Set<Int64>>? = nil
  let start: @MainActor ([Int64]) async throws -> Void
  @State private var localSelection: Set<Int64> = []
  private var selected: Set<Int64> {
    get { selection?.wrappedValue ?? localSelection }
    nonmutating set {
      if let selection { selection.wrappedValue = newValue } else { localSelection = newValue }
    }
  }
  @State private var pendingIDs: [Int64]?
  private var busy: Bool { pendingIDs != nil }
  @State private var interleave = false
  @State private var error: String?
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .title2) private var glyphSize = 28

  private struct LessonGroup: Identifiable {
    let id: String
    let title: String
    let items: [CatalogSubject]
  }
  private var groups: [LessonGroup] {
    Set(items.map(\.level)).sorted().flatMap { level in
      [SubjectKind.radical, .kanji, .vocabulary].compactMap { kind in
        let values = items.filter { $0.level == level && $0.kind == kind }.sorted { $0.id < $1.id }
        let name = kind == .radical ? "Radicals" : kind == .kanji ? "Kanji" : "Vocabulary"
        return values.isEmpty
          ? nil
          : LessonGroup(
            id: "\(level)-\(kind.rawValue)", title: "Level \(level) · \(name)", items: values)
      }
    }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if let error { Text(error).foregroundStyle(.red) }
        if items.isEmpty {
          ContentUnavailableView(
            "No lessons available", systemImage: "books.vertical",
            description: Text("Refresh your account to check for new lessons."))
        }
        ForEach(groups) { group in
          let selectionAction =
            group.items.allSatisfy { selected.contains($0.id) } ? "Clear" : "Select all"
          GroupBox {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(group.title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                  let ids = Set(group.items.map(\.id))
                  if ids.isSubset(of: selected) {
                    selected.subtract(ids)
                  } else {
                    selected.formUnion(ids)
                  }
                } label: {
                  Text(selectionAction)
                    .frame(minHeight: 44)
                }.font(.callout).accessibilityIdentifier("lesson.selectGroup.\(group.id)")
                  .accessibilityLabel("\(selectionAction) \(group.title)")
              }
              LazyVGrid(
                columns: [
                  GridItem(
                    .adaptive(
                      minimum: typeSize.isAccessibilitySize
                        || group.items.first?.kind == .vocabulary ? 156 : 84), spacing: 8)
                ], spacing: 12
              ) {
                ForEach(group.items) { tile($0) }
              }
            }
          }
        }
      }.padding(16)
    }.accessibilityIdentifier("lesson.picker").disabled(busy)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Interleave lessons", isOn: $interleave)
            .accessibilityIdentifier("lesson.interleave")
          ViewThatFits(in: .horizontal) {
            HStack {
              selectionCount.fixedSize(horizontal: true, vertical: false)
              Spacer(minLength: 12)
              startButton.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 12) {
              selectionCount
              startButton
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding().background(.bar).disabled(busy)
          .accessibilityElement(children: .contain).accessibilityLabel("Lesson controls")
          .accessibilityIdentifier("lesson.controls")
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(selected.count == items.count ? "Deselect all" : "Select all") {
            selected = selected.count == items.count ? [] : Set(items.map(\.id))
          }.disabled(items.isEmpty || busy).accessibilityIdentifier("lesson.selectAll")
        }
      }
      .onChange(of: items.map(\.id)) { _, ids in selected.formIntersection(ids) }
      .task(id: pendingIDs) {
        guard let pendingIDs else { return }
        defer { self.pendingIDs = nil }
        do {
          try Task.checkCancellation()
          try await start(pendingIDs)
        } catch {
          if !Task.isCancelled { self.error = error.localizedDescription }
        }
      }

  }
  private var selectionCount: some View {
    Text("\(selected.count) selected").monospacedDigit()
      .accessibilityIdentifier("lesson.selectionCount")
  }
  private var startButton: some View {
    Button(selected.isEmpty ? "Start a batch" : "Start lessons", systemImage: "arrow.right") {
      let chosen = items.filter { selected.isEmpty || selected.contains($0.id) }
      let queues = [SubjectKind.radical, .kanji, .vocabulary].map { kind in
        chosen.filter { $0.kind == kind }
      }
      let ordered =
        interleave
        ? (0..<(queues.map(\.count).max() ?? 0)).flatMap { index in
          queues.compactMap { $0.indices.contains(index) ? $0[index] : nil }
        } : chosen
      let ids = ordered.prefix(selected.isEmpty ? max(1, batchSize) : ordered.count).map(\.id)
      error = nil
      pendingIDs = ids
    }.buttonStyle(.glassProminent).disabled(items.isEmpty || busy)
      .accessibilityIdentifier("lesson.startSelection")
  }
  private func tile(_ item: CatalogSubject) -> some View {
    Button {
      if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    } label: {
      VStack(spacing: 4) {
        if item.japanese.isEmpty, !item.characterImageURL.isEmpty,
          let url = URL(string: item.characterImageURL)
        {
          RadicalImageView(url: url).environment(\.colorScheme, .dark)
            .frame(width: glyphSize, height: glyphSize)
        } else {
          Text(item.japanese.isEmpty ? "—" : item.japanese)
            .font(.title2)
            .lineLimit(1).minimumScaleFactor(0.5)
        }
        Text(item.summary.meaning).font(.caption).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
      }.padding(6).frame(maxWidth: .infinity).frame(
        minHeight: typeSize.isAccessibilitySize ? 132 : 84
      )
      .foregroundStyle(.white).background(
        StudyPalette.color(for: item.kind), in: RoundedRectangle(cornerRadius: 16)
      )
      .overlay {
        if selected.contains(item.id) {
          RoundedRectangle(cornerRadius: 20).strokeBorder(.primary, lineWidth: 2).padding(-4)
        }
      }
      .overlay(alignment: .topTrailing) {
        if selected.contains(item.id) {
          Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
            .foregroundStyle(.background, .primary).offset(x: 4, y: -4)
        }
      }
    }.buttonStyle(.plain)
      .accessibilityLabel(
        [item.japanese, item.summary.meaning].filter { !$0.isEmpty }.joined(separator: ", ")
      )
      .accessibilityValue(selected.contains(item.id) ? "Selected" : "Not selected")
      .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
      .accessibilityIdentifier("lesson.select.\(item.id)")
  }
}
