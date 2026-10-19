// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PromiseKit
import Reachability
import StudyCore
import StudySpeech
import WaniKaniAPI

#if !DEBUG

  // In release mode this class does nothing.
  @objc(TKMScreenshotter)
  @objcMembers
  class Screenshotter: NSObject {
    static let isActive = false
    class func setUp() {}
    static func createLocalCachingClient(
      client: WaniKaniAPIClient,
      reachability: Reachability
    ) -> LocalCachingClient {
      LocalCachingClient(client: client, reachability: reachability)
    }
  }

#else

  /// Deterministic UI-test transcription; never records audio or calls Speech APIs.
  actor SampleVoiceCapture: VoiceCapture {
    let transcript: String
    private var callback: VoiceCaptureReport?
    private var recordingID: UUID?
    init(transcript: String) { self.transcript = transcript }
    func start(
      id: UUID, locale _: Locale, downloadModel _: Bool,
      report: @escaping VoiceCaptureReport
    ) async {
      recordingID = id
      callback = report
      await report(.listening)
    }

    func finish(id: UUID) async {
      guard recordingID == id else { return }
      await callback?(.segment(text: transcript, start: 0, end: 1, isFinal: true))
      await callback?(.finished)
    }

    func cancel(id: UUID) {
      guard recordingID == id else { return }
      callback = nil
      recordingID = nil
    }
  }

  // In debug mode this class detects whether the app is being run under "fastlane snapshot", and
  // if so will provide a LocalCachingClient that returns fake data for taking screenshots for the
  // app store.
  @objc(TKMScreenshotter)
  @objcMembers
  class Screenshotter: NSObject {
    static let isActive: Bool = UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT")

    class func setUp() {
      if isActive {
        // Settings stores archived values. XCTest launch arguments arrive as strings;
        // encode known boolean overrides in the volatile domain, without changing saved
        // preferences.
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        for key in [
          "groupMeaningReading", "meaningFirst", "ankiMode", "autoSwitchKeyboard",
          "playAudioAutomatically", "reviewItemsLimitEnabled", "skipKanjiReadings",
          "allowSkippingReviews", "exactMatch", "showAnswerImmediately", "enableCheats",
          "ankiModeCombineReadingMeaning", "blurContextSentences", "allowExcludeItems",
          "showPreviousLevelGraph",
          "showAllReadings", "useKatakanaForOnyomi", "showStatsSection", "showOldMnemonic",
          "showArtwork", "showSimilarKanjiAboveLevel", "notificationsAllReviews",
          "notificationsBadging", "notificationSounds", "showFullAnswer",
          "animateParticleExplosion", "animatePlusOne", "animateLevelUpPopup",
        ] {
          if let value = arguments[key] as? String, ["YES", "NO"].contains(value),
            let data = try? NSKeyedArchiver.archivedData(
              withRootObject: value == "YES",
              requiringSecureCoding: true)
          {
            arguments[key] = data
          }
        }
        if ProcessInfo.processInfo.arguments.contains("SettingsFlowFixture"),
          let data = try? NSKeyedArchiver.archivedData(
            withRootObject: Settings.lessonOrder.map(\.rawValue), requiringSecureCoding: true)
        {
          arguments["lessonOrder"] = data
        }
        if ProcessInfo.processInfo.arguments.contains("HomeLimitFixture"),
          let data = try? NSKeyedArchiver.archivedData(
            withRootObject: 0, requiringSecureCoding: true)
        {
          arguments["apprenticeLessonsLimit"] = data
        }
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        if ProcessInfo.processInfo.arguments.contains("ResetUserDefaults")
          || ProcessInfo.processInfo.arguments.contains("LoginFlowFixture")
        {
          // We're run again after testing finishes to remove the dummy user.
          Settings.userApiToken = ""
          Settings.userEmailAddress = ""
        } else {
          // Pretend there's a logged in user.
          Settings.userApiToken = "dummy"
          Settings.userEmailAddress = "dummy"
          Settings.srsLevelIndicatorStyle = .bubble
        }
      }
    }

    static func createLocalCachingClient(
      client: WaniKaniAPIClient,
      reachability: Reachability
    ) -> LocalCachingClient {
      if isActive, ProcessInfo.processInfo.arguments.contains("ReauthFlowFixture") {
        return AccountIssueFixtureCachingClient(client: client, reachability: reachability)
      }
      if isActive, ProcessInfo.processInfo.arguments.contains("LoginFlowFixture") {
        return LoginFixtureCachingClient(client: client, reachability: reachability)
      }
      if isActive, ProcessInfo.processInfo.arguments.contains("ShellFlowFixture") {
        return ShellFixtureCachingClient(client: client, reachability: reachability)
      }
      if isActive, ProcessInfo.processInfo.arguments.contains("AudioFlowFixture") {
        return AudioFixtureCachingClient(client: client, reachability: reachability)
      }
      return isActive
        ? FakeLocalCachingClient(client: client, reachability: reachability)
        : LocalCachingClient(client: client, reachability: reachability)
    }
  }

  class FakeLocalCachingClient: LocalCachingClient {
    private var completedLessons: Set<Int64> = []
    private var editedMaterials: [Int64: StudyMaterial] =
      ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture")
      ? [3864: StudyMaterial(subjectID: 3864, meaningNote: StudyMaterial.exclusionMarker)] : [:]
    private var materialVersions: [Int64: Int64] =
      ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") ? [3864: 0] : [:]
    private var conflicts: Set<Int64> = []
    private enum Subjects {
      static let all: [Int64: TKMSubject] = [
        743: subject(
          id: 743, level: 10, japanese: "酒",
          readings: [
            reading("しゅ", primary: true, type: .onyomi),
            reading("さけ", primary: false, type: .kunyomi),
            reading("さか", primary: false, type: .kunyomi),
          ], meanings: [meaning("Alcohol", type: .primary)], kanji: .init()),
        3163: subject(
          id: 3163, level: 10, japanese: "お酒", readings: [reading("おさけ", primary: true)],
          meanings: [meaning("Sake", type: .primary), meaning("Alcohol", type: .secondary)],
          vocabulary: .init()),
        3164: subject(
          id: 3164, level: 10, japanese: "日本酒",
          readings: [reading("にほんしゅ", primary: true), reading("にっぽんしゅ", primary: false)],
          meanings: [
            meaning("Japanese Style Alcohol", type: .primary),
            meaning("Japanese Alcohol", type: .secondary), meaning("Sake", type: .secondary),
          ], vocabulary: .init()),
        355: subject(
          id: 355, level: 35, japanese: "為",
          meanings: [meaning("Sake", type: .primary), meaning("fake", type: .blacklist)],
          radical: .init()),
        1600: subject(
          id: 1600, level: 35, japanese: "為",
          readings: [
            reading("い", primary: true, type: .onyomi),
            reading("ため", primary: false, type: .kunyomi),
            reading("な", primary: false, type: .kunyomi),
            reading("す", primary: false, type: .kunyomi),
          ], meanings: [meaning("Sake", type: .primary), meaning("Fake", type: .blacklist)],
          kanji: .init()),
        8911: subject(
          id: 8911, level: 36, japanese: "鮭",
          readings: [
            reading("さけ", primary: true, type: .kunyomi),
            reading("しゃけ", primary: true, type: .kunyomi),
          ], meanings: [meaning("Salmon", type: .primary)], kanji: .init()),
        8918: subject(
          id: 8918, level: 36, japanese: "鮭",
          readings: [reading("さけ", primary: true), reading("しゃけ", primary: false)],
          meanings: [meaning("Salmon", type: .primary)], vocabulary: .init()),
        1787: subject(
          id: 1787, level: 41, japanese: "酎",
          readings: [
            reading("ちゅう", primary: true, type: .onyomi),
            reading("ちゅ", primary: true, type: .onyomi),
            reading("かも", primary: false, type: .kunyomi),
          ], meanings: [meaning("Sake", type: .primary)], kanji: .init()),
        1803: subject(
          id: 1803, level: 41, japanese: "偽",
          readings: [
            reading("ぎ", primary: true, type: .onyomi),
            reading("にせ", primary: false, type: .kunyomi),
            reading("いつわ", primary: false, type: .kunyomi),
          ], meanings: [meaning("Fake", type: .primary), meaning("Sake", type: .blacklist)],
          kanji: .init()),
        6556: subject(
          id: 6556, level: 41, japanese: "偽", readings: [reading("にせ", primary: true)],
          meanings: [
            meaning("Fake", type: .primary), meaning("Imitation", type: .secondary),
            meaning("Sake", type: .blacklist),
          ], vocabulary: .init()),
        1892: subject(
          id: 1892, level: 44, japanese: "叫",
          readings: [
            reading("きょう", primary: true, type: .onyomi),
            reading("さけ", primary: false, type: .kunyomi),
          ], meanings: [meaning("Shout", type: .primary)], kanji: .init()),
        3516: subject(
          id: 3516, level: 12, japanese: "酒飲み", readings: [reading("さけのみ", primary: true)],
          meanings: [
            meaning("Alcoholic", type: .primary), meaning("Boozer", type: .secondary),
            meaning("Drunkard", type: .secondary),
            meaning("Big Drinker", type: .auxiliaryWhitelist),
            meaning("Drinker", type: .auxiliaryWhitelist), meaning("Drink", type: .blacklist),
            meaning("alcohol", type: .blacklist),
          ], vocabulary: .init()),
        3515: subject(
          id: 3515, level: 13, japanese: "酒好き", readings: [reading("さけずき", primary: true)],
          meanings: [meaning("Drinker", type: .primary), meaning("Alcoholic", type: .secondary)],
          vocabulary: .init()),
        5907: subject(
          id: 5907, level: 35, japanese: "為に", readings: [reading("ために", primary: true)],
          meanings: [
            meaning("For", type: .primary), meaning("For The Sake Of", type: .secondary),
            meaning("To", type: .secondary), meaning("Sake Of", type: .secondary),
          ], vocabulary: .init()),
        6163: subject(
          id: 6163, level: 38, japanese: "避ける",
          readings: [reading("さける", primary: true), reading("よける", primary: false)],
          meanings: [meaning("To Avoid", type: .primary), meaning("To Dodge", type: .secondary)],
          vocabulary: .init()),
        6812: subject(
          id: 6812, level: 44, japanese: "叫ぶ", readings: [reading("さけぶ", primary: true)],
          meanings: [meaning("To Shout", type: .primary), meaning("To Scream", type: .secondary)],
          vocabulary: .init()),
        6960: subject(
          id: 6960, level: 46, japanese: "叫び", readings: [reading("さけび", primary: true)],
          meanings: [
            meaning("Shout", type: .primary), meaning("Scream", type: .secondary),
            meaning("A Shout", type: .secondary), meaning("A Scream", type: .secondary),
          ], vocabulary: .init()),
        6961: subject(
          id: 6961, level: 46, japanese: "叫び声", readings: [reading("さけびごえ", primary: true)],
          meanings: [
            meaning("Shout", type: .primary), meaning("Yell", type: .secondary),
            meaning("Scream", type: .secondary),
          ], vocabulary: .init()),
        3864: subject(
          id: 3864, level: 8, japanese: "私自身", slug: "私自身",
          documentURL: "https://www.wanikani.com/vocabulary/%E7%A7%81%E8%87%AA%E8%BA%AB",
          readings: [reading("わたしじしん", primary: true), reading("わたくしじしん", primary: false)],
          meanings: [
            meaning("Personally", type: .primary), meaning("As For Me", type: .secondary),
            meaning("Myself", type: .secondary),
          ], componentSubjectIDs: [923, 578, 689],
          vocabulary: .with {
            $0.meaningExplanation =
              "\"When it comes to <kanji>somebody</kanji> like my<kanji>self</kanji>... aka <kanji>I</kanji>...\" When you say this you're really saying \"<vocabulary>personally</vocabulary>\" or \"<vocabulary>as for me</vocabulary>.\""
            $0.readingExplanation =
              "The readings are a bit weird here. The <ja>私</ja> is <ja>わたし</ja> and the rest is on'yomi kanji readings. So, it's a mix of both, I'm afraid. \"When it comes to me, I like mixing up on'yomi and kun'yomi because I hate myself.\""
            $0.sentences = [
              .with {
                $0.japanese = "私自身は、その動物園の問題にはあまり関心がないんです。"
                $0.english = "Personally, I'm indifferent to the zoo's issues."
              },
              .with {
                $0.japanese = "私自身は、そんなにきょくたんなことじゃなければ、どんな食生活でも良いと思っています。"
                $0.english =
                  "As for me, as long as it isn't too extreme, I think any kind of diet is okay."
              },
              .with {
                $0.japanese = "あなたがもし私自身よりも私のことを知っていると思ったら、 それはとんだ大間違いよ。"
                $0.english =
                  "You’re way off base if you think you know me better than I know myself."
              },
            ]
            $0.partsOfSpeech = [.pronoun]
          }),
        923: subject(
          id: 923, japanese: "私", meanings: [meaning("I", type: .primary)], kanji: .init()),
        578: subject(
          id: 578, japanese: "自", meanings: [meaning("Self", type: .primary)], kanji: .init()),
        689: subject(
          id: 689, japanese: "身", meanings: [meaning("Somebody", type: .primary)], kanji: .init()),
        293: subject(
          id: 293, level: 24, japanese: "旦",
          meanings: [
            meaning("Dawn", type: .primary), meaning("Sunrise", type: .auxiliaryWhitelist),
          ], radical: .init()),
        294: subject(
          id: 294, level: 24, japanese: "韋",
          meanings: [
            meaning("Korea", type: .primary), meaning("Cow God", type: .auxiliaryWhitelist),
          ], radical: .init()),
        295: subject(
          id: 295, level: 24, japanese: "客", meanings: [meaning("Guest", type: .primary)],
          radical: .init()),
        296: subject(
          id: 296, level: 24, japanese: "制", meanings: [meaning("Control", type: .primary)],
          radical: .init()),
        297: subject(
          id: 297, level: 24, japanese: "然", meanings: [meaning("Nature", type: .primary)],
          radical: .init()),
        298: subject(
          id: 298, level: 24, japanese: "受", meanings: [meaning("Accept", type: .primary)],
          radical: .init()),
        1217: subject(
          id: 1217, level: 24, japanese: "担",
          readings: [reading("たん", primary: true, type: .onyomi)],
          meanings: [meaning("Carry", type: .primary), meaning("Bear", type: .secondary)],
          kanji: .init()),
        1218: subject(
          id: 1218, level: 24, japanese: "額",
          readings: [reading("がく", primary: true, type: .onyomi)],
          meanings: [
            meaning("Amount", type: .primary), meaning("Framed Picture", type: .secondary),
            meaning("Forehead", type: .secondary),
          ], kanji: .init()),
        1219: subject(
          id: 1219, level: 24, japanese: "製",
          readings: [reading("せい", primary: true, type: .onyomi)],
          meanings: [meaning("Manufacture", type: .primary)], kanji: .init()),
        1220: subject(
          id: 1220, level: 24, japanese: "違",
          readings: [reading("ちが", primary: true, type: .kunyomi)],
          meanings: [meaning("Different", type: .primary)], kanji: .init()),
        1221: subject(
          id: 1221, level: 24, japanese: "輸",
          readings: [reading("ゆ", primary: true, type: .onyomi)],
          meanings: [meaning("Transport", type: .primary)], kanji: .init()),
        1222: subject(
          id: 1222, level: 24, japanese: "燃",
          readings: [reading("ねん", primary: true, type: .onyomi)],
          meanings: [meaning("Burn", type: .primary)], kanji: .init()),
        1223: subject(
          id: 1223, level: 24, japanese: "祝",
          readings: [
            reading("しゅく", primary: true, type: .onyomi),
            reading("しゅう", primary: true, type: .onyomi),
          ], meanings: [meaning("Celebrate", type: .primary)], kanji: .init()),
        1224: subject(
          id: 1224, level: 24, japanese: "届",
          readings: [reading("とど", primary: true, type: .kunyomi)],
          meanings: [meaning("Deliver", type: .primary)], kanji: .init()),
        1225: subject(
          id: 1225, level: 24, japanese: "狭",
          readings: [
            reading("せま", primary: true, type: .kunyomi),
            reading("せば", primary: true, type: .kunyomi),
          ], meanings: [meaning("Narrow", type: .primary)], kanji: .init()),
        1226: subject(
          id: 1226, level: 24, japanese: "肩",
          readings: [reading("かた", primary: true, type: .kunyomi)],
          meanings: [meaning("Shoulder", type: .primary)], kanji: .init()),
        1227: subject(
          id: 1227, level: 24, japanese: "腕",
          readings: [reading("うで", primary: true, type: .kunyomi)],
          meanings: [meaning("Arm", type: .primary)], kanji: .init()),
        1228: subject(
          id: 1228, level: 24, japanese: "腰",
          readings: [reading("こし", primary: true, type: .kunyomi)],
          meanings: [meaning("Waist", type: .primary)], kanji: .init()),
        1229: subject(
          id: 1229, level: 24, japanese: "触",
          readings: [reading("しょく", primary: true, type: .onyomi)],
          meanings: [meaning("Touch", type: .primary)], kanji: .init()),
        1230: subject(
          id: 1230, level: 24, japanese: "載",
          readings: [reading("さい", primary: true, type: .onyomi)],
          meanings: [meaning("Publish", type: .primary)], kanji: .init()),
        1231: subject(
          id: 1231, level: 24, japanese: "層",
          readings: [reading("そう", primary: true, type: .onyomi)],
          meanings: [meaning("Layer", type: .primary)], kanji: .init()),
        1232: subject(
          id: 1232, level: 24, japanese: "型",
          readings: [reading("けい", primary: true, type: .onyomi)],
          meanings: [meaning("Model", type: .primary), meaning("Type", type: .secondary)],
          kanji: .init()),
        1233: subject(
          id: 1233, level: 24, japanese: "庁",
          readings: [reading("ちょう", primary: true, type: .onyomi)],
          meanings: [
            meaning("Agency", type: .primary), meaning("Government Office", type: .secondary),
          ], kanji: .init()),
        1234: subject(
          id: 1234, level: 24, japanese: "視",
          readings: [reading("し", primary: true, type: .onyomi)],
          meanings: [meaning("Look At", type: .primary)], kanji: .init()),
        1235: subject(
          id: 1235, level: 24, japanese: "差",
          readings: [reading("さ", primary: true, type: .onyomi)],
          meanings: [meaning("Distinction", type: .primary)], kanji: .init()),
        1236: subject(
          id: 1236, level: 24, japanese: "管",
          readings: [reading("かん", primary: true, type: .onyomi)],
          meanings: [meaning("Pipe", type: .primary)], kanji: .init()),
        1237: subject(
          id: 1237, level: 24, japanese: "象",
          readings: [
            reading("ぞう", primary: true, type: .onyomi),
            reading("しょう", primary: true, type: .onyomi),
          ],
          meanings: [meaning("Elephant", type: .primary), meaning("Phenomenon", type: .secondary)],
          kanji: .init()),
        1238: subject(
          id: 1238, level: 24, japanese: "量",
          readings: [reading("りょう", primary: true, type: .onyomi)],
          meanings: [
            meaning("Quantity", type: .primary), meaning("Amount", type: .secondary),
            meaning("quality", type: .blacklist),
          ], kanji: .init()),
        1239: subject(
          id: 1239, level: 24, japanese: "境",
          readings: [reading("きょう", primary: true, type: .onyomi)],
          meanings: [meaning("Boundary", type: .primary)], kanji: .init()),
        1240: subject(
          id: 1240, level: 24, japanese: "環",
          readings: [reading("かん", primary: true, type: .onyomi)],
          meanings: [meaning("Loop", type: .primary)], kanji: .init()),
        1241: subject(
          id: 1241, level: 24, japanese: "武",
          readings: [reading("ぶ", primary: true, type: .onyomi)],
          meanings: [meaning("Military", type: .primary)], kanji: .init()),
        1242: subject(
          id: 1242, level: 24, japanese: "質",
          readings: [
            reading("しつ", primary: true, type: .onyomi),
            reading("しち", primary: true, type: .onyomi),
          ], meanings: [meaning("Quality", type: .primary)], kanji: .init()),
        1243: subject(
          id: 1243, level: 24, japanese: "述",
          readings: [reading("じゅつ", primary: true, type: .onyomi)],
          meanings: [meaning("Mention", type: .primary)], kanji: .init()),
        1244: subject(
          id: 1244, level: 24, japanese: "供",
          readings: [reading("きょう", primary: true, type: .onyomi)],
          meanings: [meaning("Servant", type: .primary), meaning("Companion", type: .secondary)],
          kanji: .init()),
        1245: subject(
          id: 1245, level: 24, japanese: "展",
          readings: [reading("てん", primary: true, type: .onyomi)],
          meanings: [meaning("Expand", type: .primary)], kanji: .init()),
        1246: subject(
          id: 1246, level: 24, japanese: "販",
          readings: [reading("はん", primary: true, type: .onyomi)],
          meanings: [meaning("Sell", type: .primary)], kanji: .init()),
        1247: subject(
          id: 1247, level: 24, japanese: "株",
          readings: [reading("かぶ", primary: true, type: .kunyomi)],
          meanings: [meaning("Stocks", type: .primary), meaning("Shares", type: .secondary)],
          kanji: .init()),
        8790: subject(
          id: 8790, level: 24, meanings: [meaning("Death Star", type: .primary)],
          radical: .with {
            $0.characterImage =
              "https://cdn.wanikani.com/images/363-subject-8790-with-css-original.svg?1520987154"
            $0.hasCharacterImageFile_p = true
          }),
      ]
      private static func subject(
        id: Int64, level: Int32? = nil, japanese: String? = nil, slug: String? = nil,
        documentURL: String? = nil, readings: [TKMReading] = [], meanings: [TKMMeaning] = [],
        componentSubjectIDs: [Int64] = [], radical: TKMRadical? = nil, kanji: TKMKanji? = nil,
        vocabulary: TKMVocabulary? = nil
      ) -> TKMSubject {
        .with {
          $0.id = id
          if let level { $0.level = level }
          if let japanese { $0.japanese = japanese }
          if let slug { $0.slug = slug }
          if let documentURL { $0.documentURL = documentURL }
          $0.readings = readings
          $0.meanings = meanings
          $0.componentSubjectIds = componentSubjectIDs
          if let radical { $0.radical = radical }
          if let kanji { $0.kanji = kanji }
          if let vocabulary { $0.vocabulary = vocabulary }
        }
      }
      private static func reading(
        _ text: String, primary: Bool? = nil, type: TKMReading.TypeEnum? = nil
      ) -> TKMReading {
        .with {
          $0.reading = text
          if let primary { $0.isPrimary = primary }
          if let type { $0.type = type }
        }
      }
      private static func meaning(_ text: String, type: TKMMeaning.TypeEnum? = nil) -> TKMMeaning {
        .with {
          $0.meaning = text
          if let type { $0.type = type }
        }
      }
    }

    override func countRows(inTable _: String) -> Int {
      0
    }

    private func createComposition(_ source: Int...) -> [ReviewComposition] {
      var composition: [ReviewComposition] = []
      for reviews in source {
        composition.append(
          ReviewComposition(
            availableReviews: reviews,
            countByType: [.radical: reviews],
            countByCategory: [.apprentice: 0]))
      }
      return composition
    }

    override func updateAvailableSubjects() -> (Int, [ReviewComposition]) {
      if ProcessInfo.processInfo.arguments.contains("HomeEmptyFixture") {
        return (0, createComposition(0))
      }
      if ProcessInfo.processInfo.arguments.contains("LessonFlowFixture") {
        return (getAllAssignments().filter(\.isLessonStage).count, createComposition(0))
      }
      return (
        10,
        createComposition(
          getAllAssignments().count, 14, 8, 2, 1, 12, 42, 17, 9, 2, 0, 2, 17, 0, 0,
          6, 0, 0, 0, 0,
          4, 11, 0, 8, 6)
      )
    }

    override func updateGuruKanjiCount() -> Int {
      864
    }

    override func updateSrsCategoryCounts() -> [Int] {
      guard ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") else {
        return [86, 120, 485, 786, 2056]
      }
      var counts = Array(repeating: 0, count: 6)
      for item in catalogAssignments() where !item.isLocked && item.srsStageNumber > 0 {
        counts[item.srsStage.category.rawValue] += 1
      }
      return counts
    }

    override func getSubject(id: Int64) -> TKMSubject? {
      if var subject = Subjects.all[id] {
        if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") {
          subject.level = [Int64(294): Int32(2), 923: 2][id] ?? 1
        }
        return subject
      }
      return nil
    }

    override func levelOf(subjectId: Int64) -> Int? {
      getSubject(id: subjectId).map { Int($0.level) }
    }

    override func getAllSubjects() -> [TKMSubject] {
      Subjects.all.keys.sorted().compactMap { getSubject(id: $0) }
    }

    override func getAllAssignments() -> [TKMAssignment] {
      if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") {
        return catalogAssignments()
      }
      if ProcessInfo.processInfo.arguments.contains("LessonFlowFixture") {
        return [Int64(293), 743, 3864].map { id in
          let subject = getSubject(id: id)!
          var assignment = TKMAssignment()
          assignment.id = 100_000 + id
          assignment.subjectID = id
          assignment.subjectType = subject.subjectType
          assignment.level = subject.level
          assignment.srsStageNumber = completedLessons.contains(id) ? 1 : 0
          if completedLessons.contains(id) {
            assignment.startedAt = 100
            assignment.availableAt = Int32.max
          }
          return assignment
        }
      }
      // Distinct subjects keep the sample review count consistent with statistics.
      let feedbackFixture = ProcessInfo.processInfo.arguments.contains("ReviewFeedbackFixture")
      let ids: [Int64] =
        feedbackFixture
        ? [3864, 923]
        : ProcessInfo.processInfo.arguments
          .contains("VoiceReviewFixture")
          || ProcessInfo.processInfo.arguments
            .contains("SingleReviewFixture")
          ? [3864] : [3864, 923, 578, 689]
      return ids.map { id in
        var a = TKMAssignment()
        a.subjectID = id
        a.subjectType = id == 3864 ? .vocabulary : .kanji
        a.availableAt = 42
        a.srsStageNumber = feedbackFixture ? 4 : 2
        return a
      }
    }

    private func catalogAssignments() -> [TKMAssignment] {
      [Int64(293), 294, 743, 923, 578, 3864, 689, 8790].map { id in
        let subject = getSubject(id: id)!
        var value = TKMAssignment()
        value.id = 100_000 + id
        value.subjectID = id
        value.subjectType = subject.subjectType
        value.level = subject.level
        if ![294, 8790].contains(id) {
          value.srsStageNumber = [Int64(293): Int32(5), 743: 2, 923: 5, 578: 0, 3864: 3, 689: 9][
            id]!
          if value.srsStageNumber > 0 {
            value.startedAt = 42
            value.availableAt = id == 923 ? Int32.max : 42
          }
        }
        return value
      }
    }
    override func getAssignmentsInCategory(category: SRSStageCategory) -> [TKMAssignment] {
      if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") {
        return catalogAssignments().filter { !$0.isLocked && $0.srsStage.category == category }
      }
      return super.getAssignmentsInCategory(category: category)
    }

    override func getAllReviewStatistics() -> [TKMReviewStatistic] {
      var result = [TKMReviewStatistic]()
      for index in 0..<12 {
        var stat = TKMReviewStatistic()
        stat.subjectID = index == 0 ? 3864 : Int64(1200 + index)
        stat.type = .vocabulary
        stat.meaningCorrect = 24
        stat.meaningIncorrect = 2
        stat.meaningCurrentStreak = 8
        stat.readingCorrect = 16
        stat.readingIncorrect = index == 0 ? 8 : 3
        stat.readingCurrentStreak = index == 0 ? 0 : 5
        result.append(stat)
      }
      return result
    }

    override func getAllLevelProgressions() -> [TKMLevel] {
      var result = [TKMLevel]()
      var start = Date().addingTimeInterval(-95 * 86400)
      for (index, days) in [10, 12, 11, 14, 9, 13, 12, 13].enumerated() {
        var level = TKMLevel()
        level.level = Int32(16 + index)
        level.unlockedAt = Int32(start.timeIntervalSince1970)
        start = start.addingTimeInterval(Double(days) * 86400)
        level.passedAt = Int32(start.timeIntervalSince1970)
        result.append(level)
      }
      var current = TKMLevel()
      current.level = 24
      current.unlockedAt = Int32(Date().addingTimeInterval(-86400).timeIntervalSince1970)
      result.append(current)
      return result
    }

    override func getStudyMaterial(subjectId: Int64) -> TKMStudyMaterials? {
      guard let material = editedMaterials[subjectId] else { return nil }
      var value = TKMStudyMaterials()
      value.subjectID = subjectId
      value.meaningNote = material.meaningNote
      value.readingNote = material.readingNote
      value.meaningSynonyms = material.meaningSynonyms
      return value
    }

    override func editableStudyMaterial(subjectID: Int64, account: String) -> StudyMaterialEdit<
      Int64
    >? {
      guard account == getUserInfo()?.username else { return nil }
      return StudyMaterialEdit(
        material: editedMaterials[subjectID] ?? StudyMaterial(subjectID: subjectID),
        version: materialVersions[subjectID])
    }

    override func saveEditedStudyMaterial(
      _ material: StudyMaterial, expectedRevision: Int64?, account: String
    ) -> Bool {
      guard account == getUserInfo()?.username else { return false }
      if ProcessInfo.processInfo.arguments.contains("MaterialConflictFixture"),
        conflicts.insert(material.subjectID).inserted
      {
        editedMaterials[material.subjectID] = StudyMaterial(
          subjectID: material.subjectID,
          meaningNote: "Concurrent saved note\n" + StudyMaterial.exclusionMarker,
          readingNote: "Concurrent hidden reading note")
        materialVersions[material.subjectID, default: 0] += 1
      }
      guard materialVersions[material.subjectID] == expectedRevision else { return false }
      editedMaterials[material.subjectID] = material
      materialVersions[material.subjectID, default: 0] += 1
      return true
    }

    override func getUserInfo() -> TKMUser? {
      var user = TKMUser()
      user.level = 24
      if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") { user.level = 1 }
      if ProcessInfo.processInfo.arguments.contains("HomeVacationFixture") {
        user.vacationStartedAt = 50
      }
      user.username = "Fred"
      user.maxLevelGrantedBySubscription = 60
      return user
    }

    override func getAllPendingProgress(limit _: Int?) -> [TKMProgress] {
      []
    }

    override func getAssignment(subjectId _: Int64) -> TKMAssignment? {
      nil
    }

    override func getAssignments(level: Int) -> [TKMAssignment] {
      if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") {
        return catalogAssignments().filter { $0.level == level }
      }
      // Return just enough to populate the level catalog.
      let subjects = [
        293,
        294,
        295,
        296,
        297,
        298,
        1217,
        1218,
        1219,
        1220,
        1221,
        1222,
        1223,
        1224,
        1225,
        1226,
        1227,
        1228,
        1229,
        1230,
        1231,
        1232,
        1233,
        1234,
        1235,
        1236,
        1237,
        1238,
        1239,
        1240,
        1241,
        1242,
        1243,
        1244,
        1245,
        1246,
        1247,
        8790,
      ].map {
        getSubject(id: $0)!
      }

      srand48(42)

      var ret = [TKMAssignment]()
      for s in subjects {
        var a = TKMAssignment()
        a.subjectID = s.id
        a.subjectType = s.subjectType

        if a.subjectType == .radical {
          a.srsStageNumber = 5
        } else {
          a.srsStageNumber = Int32(drand48() * 6)
        }
        ret.append(a)
      }
      return ret
    }

    override func getAssignmentsAtUsersCurrentLevel() -> [TKMAssignment] {
      if ProcessInfo.processInfo.arguments.contains("CatalogFlowFixture") {
        return catalogAssignments().filter { $0.level == 1 }
      }
      return makePieSlices(.radical, locked: 0, lesson: 2, apprentice: 4, guru: 1)
        + makePieSlices(.kanji, locked: 8, lesson: 4, apprentice: 12, guru: 1)
        + makePieSlices(.vocabulary, locked: 50, lesson: 8, apprentice: 4, guru: 0)
    }

    override func sendProgress(_ progress: [TKMProgress]) -> Promise<Void> {
      if ProcessInfo.processInfo.arguments.contains("LessonFlowFixture") {
        completedLessons.formUnion(progress.filter(\.isLesson).map { $0.assignment.subjectID })
      }
      return Promise.value(())
    }

    override func updateStudyMaterial(_ value: TKMStudyMaterials) -> Promise<Void> {
      editedMaterials[value.subjectID] = StudyMaterial(
        subjectID: value.subjectID, meaningNote: value.meaningNote,
        readingNote: value.readingNote, meaningSynonyms: value.meaningSynonyms)
      materialVersions[value.subjectID, default: 0] += 1
      return Promise.value(())
    }

    override func clearAllData() {}

    override func clearAllDataAndClose() {}

    private func makeAssignment(_ type: TKMSubject.TypeEnum, srsStage: Int32) -> TKMAssignment {
      var ret = TKMAssignment()
      ret.subjectType = type
      if srsStage != -1 {
        ret.srsStageNumber = srsStage
      }
      return ret
    }

    private func makePieSlices(
      _ type: TKMSubject.TypeEnum,
      locked: Int,
      lesson: Int,
      apprentice: Int,
      guru: Int
    ) -> [TKMAssignment] {
      Array(repeating: makeAssignment(type, srsStage: -1), count: locked)
        + Array(repeating: makeAssignment(type, srsStage: 0), count: lesson)
        + Array(repeating: makeAssignment(type, srsStage: 1), count: apprentice)
        + Array(repeating: makeAssignment(type, srsStage: 6), count: guru)
    }

    override func sync(quick _: Bool, progress _: Progress) -> PMKFinalizer {
      Promise.value(()).cauterize()
    }
  }

#endif
