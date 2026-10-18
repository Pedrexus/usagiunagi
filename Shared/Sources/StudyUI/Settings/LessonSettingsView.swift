import StudyCore
import SwiftUI

public struct LessonSettingsView<AdditionalVocabulary: View>: View {
  @Bindable private var settings: StudyLessonSettings
  private let additionalVocabulary: AdditionalVocabulary
  public init(
    settings: StudyLessonSettings, @ViewBuilder additionalVocabulary: () -> AdditionalVocabulary
  ) {
    self.settings = settings
    self.additionalVocabulary = additionalVocabulary()
  }
  public init(settings: StudyLessonSettings) where AdditionalVocabulary == EmptyView {
    self.init(settings: settings) { EmptyView() }
  }
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
  public var body: some View {
    Form {
      Section {
        NavigationLink {
          List {
            ForEach(settings.value.order, id: \.self) { kind in
              HStack {
                Text(title(kind))
                #if os(macOS)
                  Spacer()
                  Button("Move \(title(kind)) up", systemImage: "chevron.up") {
                    shift(kind, by: -1)
                  }
                  .disabled(settings.value.order.first == kind).labelStyle(.iconOnly)
                  .accessibilityIdentifier(
                    "settings.lessonOrder.up.\(kind.rawValue)")
                  Button("Move \(title(kind)) down", systemImage: "chevron.down") {
                    shift(kind, by: 1)
                  }
                  .disabled(settings.value.order.last == kind).labelStyle(.iconOnly)
                  .accessibilityIdentifier(
                    "settings.lessonOrder.down.\(kind.rawValue)")
                #endif
              }
            }.onMove(perform: move)
          }
          #if os(iOS)
            .environment(\.editMode, .constant(.active))
          #endif
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
        additionalVocabulary
      }
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .navigationTitle("Lessons").task { settings.reload() }
  }
  private func move(_ source: IndexSet, _ destination: Int) {
    var value = settings.value
    value.order.move(fromOffsets: source, toOffset: destination)
    settings.applyChanges(from: settings.value, to: value)
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
