import StudyCore
import SwiftUI

/// The original level/type grid, with native selection and host-owned lesson validation.
public struct LessonPickerView: View {
  private let items: [StudySubject]
  private let japaneseFont: String?
  private let image: (Int64) -> Image?
  private let start: @MainActor ([Int64]) async throws -> Void
  @State private var localSelection: Set<Int64> = []
  private let selection: Binding<Set<Int64>>?
  private var selected: Set<Int64> {
    get { selection?.wrappedValue ?? localSelection }
    nonmutating set {
      if let selection { selection.wrappedValue = newValue } else { localSelection = newValue }
    }
  }
  @State private var busy = false
  @State private var error: String?
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .title2) private var glyphSize = 28

  public init(
    items: [StudySubject], selection: Binding<Set<Int64>>? = nil, japaneseFont: String? = nil,
    image: @escaping (Int64) -> Image? = { _ in nil },
    start: @escaping @MainActor ([Int64]) async throws -> Void
  ) {
    self.items = items
    self.selection = selection
    self.japaneseFont = japaneseFont
    self.image = image
    self.start = start
  }
  private struct LessonGroup: Identifiable {
    let id: String
    let title: String
    let items: [StudySubject]
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
  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if let error { Text(error).foregroundStyle(.red) }
        if items.isEmpty {
          ContentUnavailableView(
            "No lessons available", systemImage: "books.vertical",
            description: Text("Refresh your account to check for new lessons."))
        }
        ForEach(groups) { group in
          Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 8)
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: 8),
              count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 12
          ) {
            ForEach(group.items) { tile($0) }
          }
        }
      }.padding(16)
    }.disabled(busy)
      .safeAreaInset(edge: .bottom) {
        HStack {
          Text("\(selected.count) selected").monospacedDigit().accessibilityIdentifier(
            "lesson.selectionCount")
          Spacer()
          Button("Start lessons", systemImage: "arrow.right") {
            let ids = groups.flatMap(\.items).map(\.id).filter { selected.contains($0) }
            busy = true
            error = nil
            Task {
              defer { busy = false }
              do { try await start(ids) } catch { self.error = error.localizedDescription }
            }
          }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || busy)
            .accessibilityIdentifier("lesson.startSelection")
        }.padding().background(.bar)
      }
      .onChange(of: items.map(\.id)) { _, ids in selected.formIntersection(ids) }
  }
  private func tile(_ item: StudySubject) -> some View {
    Button {
      if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    } label: {
      VStack(spacing: 4) {
        if let image = image(item.id) {
          image.resizable().scaledToFit().frame(width: glyphSize, height: glyphSize)
        } else {
          Text(item.characters.isEmpty ? "—" : item.characters)
            .font(japaneseFont.map { .custom($0, size: glyphSize, relativeTo: .title2) } ?? .title2)
            .lineLimit(1).minimumScaleFactor(0.5)
        }
        Text(item.meaning).font(.caption).lineLimit(1)
      }.padding(6).frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 132 : 84)
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
        [item.characters, item.meaning].filter { !$0.isEmpty }.joined(separator: ", ")
      )
      .accessibilityValue(selected.contains(item.id) ? "Selected" : "Not selected")
      .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
      .accessibilityIdentifier("lesson.select.\(item.id)")
  }
}
