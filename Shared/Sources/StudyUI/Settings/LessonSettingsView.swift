import StudyCore
import SwiftUI

struct LessonSettingsView: View {
  @Bindable var settings: StudyLessonSettings
  private var binding: Binding<StudyLessonPreferences> {
    Binding(get: { settings.value }, set: { settings.applyChanges(from: settings.value, to: $0) })
  }
  private func title(_ kind: SubjectKind) -> String {
    switch kind {
    case .radical: "Radicals"
    case .kanji: "Kanji"
    case .vocabulary: "Vocabulary"
    }
  }
  var body: some View {
    Form {
      Section {
        NavigationLink {
          List {
            Section {
              ForEach(settings.value.order, id: \.self) { kind in
                Text(title(kind))
                  .accessibilityActions {
                    if settings.value.order.first != kind {
                      Button("Move \(title(kind)) up", systemImage: "chevron.up") {
                        shift(kind, by: -1)
                      }
                      .accessibilityIdentifier("settings.lessonOrder.up.\(kind.rawValue)")
                    }
                    if settings.value.order.last != kind {
                      Button("Move \(title(kind)) down", systemImage: "chevron.down") {
                        shift(kind, by: 1)
                      }
                      .accessibilityIdentifier("settings.lessonOrder.down.\(kind.rawValue)")
                    }
                  }
              }.reorderable()
            } footer: {
              Text("Drag items to change the lesson order.")
            }
          }
          .reorderContainer(for: SubjectKind.self, itemID: \.self, move: move)
          .navigationTitle("Lesson order").accessibilityIdentifier("settings.lessonOrder")
        } label: {
          LabeledContent("Order", value: settings.value.order.map(title).joined(separator: ", "))
        }.accessibilityIdentifier("settings.lessonOrderLink")
        Picker("Batch size", selection: binding.batchSize) {
          ForEach(1...10, id: \.self) { Text($0 == 1 ? "1 lesson" : "\($0) lessons").tag($0) }
        }.accessibilityIdentifier("settings.lessonBatchSize")
        Toggle("Prioritize current level", isOn: binding.prioritizeCurrentLevel)
          .accessibilityIdentifier("settings.prioritizeCurrentLevel")
        Picker("Apprentice limit", selection: binding.apprenticeLimit) {
          Text("No limit").tag(Int.max)
          ForEach(Array(stride(from: 25, through: 200, by: 25)), id: \.self) {
            Text($0.formatted()).tag($0)
          }
        }.accessibilityIdentifier("settings.apprenticeLessonsLimit")
      } header: {
        Text("Lessons")
      } footer: {
        Text(
          "The batch size controls how many new items are introduced before a quiz. The apprentice limit stops new lessons when you have that many Apprentice items."
        )
      }
      Section("Vocabulary") {
        Toggle("Show kana-only vocabulary", isOn: binding.includeKanaVocabulary)
          .accessibilityIdentifier("settings.showKanaOnlyVocab")
        Text("Include lessons and reviews for vocabulary written only in kana.").font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Allow excluding vocabulary items", isOn: binding.allowVocabularyExclusion)
          .accessibilityIdentifier("settings.allowExcludeItems")
        Text("Show the option to exclude vocabulary from lessons and reviews.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Lessons").task { settings.reload() }
  }
  private func move(
    _ difference: ReorderDifference<SubjectKind, ReorderableSingleCollectionIdentifier>
  ) {
    let previous = settings.value
    let moving = difference.sources
    guard !moving.isEmpty, Set(moving).count == moving.count,
      moving.allSatisfy(previous.order.contains)
    else { return }
    var value = previous
    value.order.removeAll { moving.contains($0) }
    switch difference.destination.position {
    case .before(let kind):
      guard let index = value.order.firstIndex(of: kind) else { return }
      value.order.insert(contentsOf: moving, at: index)
    case .end:
      value.order.append(contentsOf: moving)
    }
    settings.applyChanges(from: previous, to: value)
  }
  private func shift(_ kind: SubjectKind, by offset: Int) {
    guard let index = settings.value.order.firstIndex(of: kind) else { return }
    let target = index + offset
    guard settings.value.order.indices.contains(target) else { return }
    var value = settings.value
    value.order.swapAt(index, target)
    settings.applyChanges(from: settings.value, to: value)
  }
}
