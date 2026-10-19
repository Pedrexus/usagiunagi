// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore
import Testing

@Suite(.serialized) @MainActor struct ReviewPreferencesAdapterTest {
  private let keys = [
    "interfaceStyle", "srsLevelIndicatorStyle", "fontSize", "showAnswerImmediately",
    "showFullAnswer",
    "exactMatch", "enableCheats", "allowSkippingReviews", "playAudioAutomatically",
    "interruptBackgroundAudio", "animateParticleExplosion", "animatePlusOne", "animateLevelUpPopup",
    "reviewOrder", "reviewItemsLimitEnabled", "reviewItemsLimit", "leechThreshold", "ankiMode",
    "ankiModeTaskType", "ankiModeCombineReadingMeaning", "reviewBatchSize", "groupMeaningReading",
    "meaningFirst", "incorrectAnswerReturnDelay", "skipKanjiReadings", "minimizeReviewPenalty",
  ]
  private func preservingArchives(_ test: () throws -> Void) rethrows {
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, saved) {
        if let value {
          UserDefaults.standard.set(value, forKey: key)
        } else {
          UserDefaults.standard.removeObject(forKey: key)
        }
      }
    }
    try test()
  }
  @Test func mapsExistingArchivesAndKeepsTheirStorageFormat() {
    preservingArchives {
      Settings.interfaceStyle = .light
      Settings.srsLevelIndicatorStyle = .dots
      Settings.fontSize = 1.25
      let old = ReviewPreferencesAdapter.current
      #expect(old.appearance == .light && old.stageIndicator == .dots && old.fontScale == 1.25)
      var new = old
      new.appearance = .dark
      new.stageIndicator = .none
      new.fontScale = 1.75
      new.revealAnswers.toggle()
      new.revealFullAnswer.toggle()
      new.exactMatch.toggle()
      new.allowCorrections.toggle()
      new.allowSkipping.toggle()
      new.autoplayAudio.toggle()
      new.interruptBackgroundAudio.toggle()
      new.correctAnswerFeedback.toggle()
      new.completedItemFeedback.toggle()
      new.srsMilestoneFeedback.toggle()
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(ReviewPreferencesAdapter.current == new)
      #expect(Settings.animateParticleExplosion == new.correctAnswerFeedback)
      #expect(
        Settings.animatePlusOne == new.completedItemFeedback
          && Settings.animateLevelUpPopup == new.srsMilestoneFeedback)
      #expect(keys.prefix(13).allSatisfy { UserDefaults.standard.object(forKey: $0) is Data })
    }
  }
  @Test func appliesOnlyChangedFieldsIncludingSessionAndPolicy() {
    preservingArchives {
      let old = ReviewPreferencesAdapter.current
      Settings.playAudioAutomatically = !old.autoplayAudio
      Settings.animatePlusOne = !old.completedItemFeedback
      Settings.reviewBatchSize = old.sessionOptions.batchSize + 1
      Settings.reviewItemsLimit = old.policy.limit + 5
      var new = old
      new.exactMatch.toggle()
      new.sessionOptions.meaningFirst.toggle()
      new.policy.limitEnabled.toggle()
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(
        Settings.exactMatch == new.exactMatch
          && Settings.meaningFirst == new.sessionOptions.meaningFirst)
      #expect(
        Settings.playAudioAutomatically == !old.autoplayAudio
          && Settings.animatePlusOne == !old.completedItemFeedback)
      #expect(
        Settings.reviewBatchSize == old.sessionOptions.batchSize + 1
          && Settings.reviewItemsLimit == old.policy.limit + 5)
      #expect(Settings.reviewItemsLimitEnabled == new.policy.limitEnabled)
    }
  }
  @Test(arguments: StudyReviewOrder.allCases) func originalOrderingCodesRemainArchived(
    order: StudyReviewOrder
  ) {
    preservingArchives {
      let old = ReviewPreferencesAdapter.current
      var new = old
      new.policy.order = order
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(Settings.reviewOrder.rawValue == order.rawValue)
      #expect(Settings.reviewOrder.description == order.description)
      #expect(ReviewPreferencesAdapter.current.policy.order == order)
    }
  }
  @Test func fullSessionOptionsRoundTripAndDriveTheExistingEngine() {
    preservingArchives {
      let old = ReviewPreferencesAdapter.current
      var new = old
      new.policy.limitEnabled.toggle()
      new.policy.limit += 7
      new.policy.leechThreshold = 2.75
      new.sessionOptions.ankiMode = .both
      new.sessionOptions.combinedAnki = true
      new.sessionOptions.batchSize += 1
      new.sessionOptions.groupMeaningReading.toggle()
      new.sessionOptions.meaningFirst.toggle()
      new.sessionOptions.incorrectAnswerDelay += 1
      new.sessionOptions.skipKanjiReadings.toggle()
      new.sessionOptions.minimizePenalty.toggle()
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(ReviewPreferencesAdapter.current == new)
      #expect(ReviewSession.currentOptions() == new.sessionOptions)
      Settings.meaningFirst.toggle()
      #expect(ReviewSession.currentOptions().meaningFirst == !new.sessionOptions.meaningFirst)
    }
  }
  @Test func disablingAnkiPreservesTaskArchiveButClearsCombinedMode() {
    preservingArchives {
      Settings.ankiMode = true
      Settings.ankiModeTaskType = .both
      Settings.ankiModeCombineReadingMeaning = true
      var old = ReviewPreferencesAdapter.current
      var new = old
      new.sessionOptions.ankiMode = .reading
      new.sessionOptions.combinedAnki = false
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(Settings.ankiModeTaskType == .readingOnly && !Settings.ankiModeCombineReadingMeaning)
      old = ReviewPreferencesAdapter.current
      new = old
      new.sessionOptions.ankiMode = .off
      ReviewPreferencesAdapter.apply(new, replacing: old)
      #expect(
        !Settings.ankiMode && Settings.ankiModeTaskType == .readingOnly
          && !Settings.ankiModeCombineReadingMeaning)
    }
  }
}
