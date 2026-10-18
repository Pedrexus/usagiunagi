// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import SwiftUI

struct SubjectDisplaySettings: View {
  var body: some View {
    Form {
      Section("Readings") {
        SettingToggle(
          "Use Katakana for Onyomi", Settings.$useKatakanaForOnyomi,
          help: "Show Onyomi kanji readings in Katakana instead of Hiragana")
        SettingToggle(
          "Show all kanji readings", Settings.$showAllReadings,
          help: "Primary readings appear in bold")
        SettingToggle(
          "Skip Kanji readings", Settings.$skipKanjiReadings,
          help:
            "Do not quiz kanji readings during lessons or reviews. Vocabulary readings are still tested."
        )
      }
      Section("Details pages") {
        SettingToggle(
          "Show stats section", Settings.$showStatsSection,
          help: "Level, SRS stage and answer history")
        SettingToggle(
          "Show old mnemonics", Settings.$showOldMnemonic,
          help: "Include radical mnemonics removed in 2018")
        SettingToggle(
          "Hide context translations", Settings.$blurContextSentences,
          help: "Reveal English translations only when you choose to show them")
        SettingToggle(
          "Show artwork by @AmandaBear", Settings.$showArtwork,
          help: "Mnemonic artwork for radical levels 1–10 and kanji levels 1–7")
        SettingToggle(
          "Show prior level graph until fully completed", Settings.$showPreviousLevelGraph,
          help: "Keep the graph until its radicals, kanji and vocabulary reach Guru")
        SettingToggle(
          "Show visually similar kanji above current level", Settings.$showSimilarKanjiAboveLevel,
          help: "Include similar kanji you have not unlocked yet")
      }
    }.navigationTitle("Subject details")
  }
}
