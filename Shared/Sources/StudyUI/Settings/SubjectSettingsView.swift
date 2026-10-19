import StudyCore
import SwiftUI

/// Display choices share one owner; skipping readings stays with the review-session policy.
public struct SubjectSettingsView: View {
  private let settings: StudySubjectSettings
  @Binding private var skipKanjiReadings: Bool
  public init(settings: StudySubjectSettings, skipKanjiReadings: Binding<Bool>) {
    self.settings = settings
    _skipKanjiReadings = skipKanjiReadings
  }
  private func binding(_ key: WritableKeyPath<SubjectDetailsPreferences, Bool>) -> Binding<Bool> {
    Binding(
      get: { settings.value[keyPath: key] },
      set: { value in
        let old = settings.value
        var new = old
        new[keyPath: key] = value
        settings.applyChanges(from: old, to: new)
      })
  }
  public var body: some View {
    Form {
      Section("Readings") {
        choice(
          "Use Katakana for Onyomi", \.useKatakanaForOnyomi, id: "useKatakanaForOnyomi",
          help: "Show Onyomi kanji readings in Katakana instead of Hiragana")
        Toggle(
          "Show all kanji readings",
          isOn: Binding(
            get: { !settings.value.primaryKanjiReadingsOnly },
            set: { binding(\.primaryKanjiReadingsOnly).wrappedValue = !$0 })
        )
        .accessibilityIdentifier("settings.showAllReadings")
        Text("Primary readings appear in bold").font(.caption).foregroundStyle(.secondary)
        Toggle("Skip Kanji readings", isOn: $skipKanjiReadings)
          .accessibilityIdentifier("settings.skipKanjiReadings")
        Text(
          "Do not quiz kanji readings during lessons or reviews. Vocabulary readings are still tested."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Details pages") {
        choice(
          "Show stats section", \.showStatistics, id: "showStatsSection",
          help: "Level, SRS stage and study dates")
        choice(
          "Show old mnemonics", \.showDeprecatedMnemonic, id: "showOldMnemonic",
          help: "Include radical mnemonics removed in 2018")
        choice(
          "Hide context translations", \.blurTranslations, id: "blurContextSentences",
          help: "Reveal English translations only when you choose to show them")
        choice(
          "Show artwork by @AmandaBear", \.showArtwork, id: "showArtwork",
          help: "Mnemonic artwork for radical levels 1–10 and kanji levels 1–7")
        choice(
          "Show prior level graph until fully completed", \.showPreviousLevelGraph,
          id: "showPreviousLevelGraph",
          help: "Keep the graph until its radicals, kanji and vocabulary reach Guru")
        choice(
          "Show visually similar kanji above current level", \.showSimilarKanjiAboveCurrentLevel,
          id: "showSimilarKanjiAboveLevel", help: "Include similar kanji you have not unlocked yet")
      }
    }.formStyle(.grouped).toggleStyle(.switch).navigationTitle("Subject details")
  }
  private func choice(
    _ title: String, _ key: WritableKeyPath<SubjectDetailsPreferences, Bool>, id: String,
    help: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle(title, isOn: binding(key)).accessibilityIdentifier("settings.\(id)")
      Text(help).font(.caption).foregroundStyle(.secondary)
    }
  }
}
