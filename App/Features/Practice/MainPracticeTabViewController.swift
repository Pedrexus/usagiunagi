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
import StudyCore
import StudyUI
import SwiftUI
import WaniKaniAPI

final class MainPracticeTabViewController: UIHostingController<KatakanaPracticeMenu> {
  var services: TKMServices!

  required init?(coder: NSCoder) {
    super.init(coder: coder, rootView: KatakanaPracticeMenu {})
  }

  func setup(services: TKMServices) {
    self.services = services
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    rootView = KatakanaPracticeMenu { [weak self] in
      self?.perform(segue: StoryboardSegue.Main.katakanaCharacterPractice, sender: self)
    }
  }

  // MARK: - UIViewController

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    switch StoryboardSegue.Main(segue) {
    case .katakanaCharacterPractice:
      var items = [ReviewItem]()
      for japanese in KatakanaPractice.characters {
        var subject = TKMSubject()
        subject.japanese = japanese
        subject.vocabulary = TKMVocabulary()

        var reading = TKMReading()
        reading.reading = japanese.applyingTransform(.hiraganaToKatakana, reverse: true)!
        subject.readings.append(reading)

        var assignment = TKMAssignment()
        assignment.subjectType = .vocabulary

        items.append(ReviewItem(assignment: assignment, subject: subject))
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    default:
      break
    }
  }
}
