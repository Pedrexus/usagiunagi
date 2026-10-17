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

import StudyCore
import XCTest

final class ReviewPreferencesAdapterTest: XCTestCase {
  private let keys = [
    "interfaceStyle",
    "srsLevelIndicatorStyle",
    "fontSize",
    "showAnswerImmediately",
    "showFullAnswer",
    "exactMatch",
    "enableCheats",
    "allowSkippingReviews",
    "playAudioAutomatically",
    "interruptBackgroundAudio",
  ]
  private var saved: [String: Any] = [:]

  override func setUp() {
    super.setUp()
    for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
  }

  override func tearDown() {
    for key in keys {
      if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
      else { UserDefaults.standard.removeObject(forKey: key) }
    }
    super.tearDown()
  }

  func testMapsExistingArchivedSettingsAndKeepsTheirStorageFormat() {
    Settings.interfaceStyle = .light
    Settings.srsLevelIndicatorStyle = .dots
    Settings.fontSize = 1.25
    let old = ReviewPreferencesAdapter.current
    XCTAssertEqual(old.appearance, .light)
    XCTAssertEqual(old.stageIndicator, .dots)
    XCTAssertEqual(old.fontScale, 1.25)
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
    ReviewPreferencesAdapter.apply(new, replacing: old)
    XCTAssertEqual(ReviewPreferencesAdapter.current, new)
    XCTAssertEqual(Settings.interfaceStyle, .dark)
    XCTAssertEqual(Settings.srsLevelIndicatorStyle, .none)
    for key in keys { XCTAssertTrue(UserDefaults.standard.object(forKey: key) is Data, key) }
  }

  func testAppliesOnlyChangedFields() {
    let old = ReviewPreferencesAdapter.current
    Settings.playAudioAutomatically = !old.autoplayAudio
    var new = old
    new.exactMatch.toggle()
    ReviewPreferencesAdapter.apply(new, replacing: old)
    XCTAssertEqual(Settings.exactMatch, new.exactMatch)
    XCTAssertEqual(Settings.playAudioAutomatically, !old.autoplayAudio)
  }
}
