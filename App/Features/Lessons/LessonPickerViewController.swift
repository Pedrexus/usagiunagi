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
import StudyUI
import SwiftUI
import WaniKaniAPI

/// Navigation/repository adapter until the iOS shell moves to SwiftUI.
final class LessonPickerViewController: UIHostingController<LessonPickerView?>, TKMViewController {
  private var services: TKMServices!
  private var selectedItems: [ReviewItem] = []
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices) { self.services = services }
  var canSwipeToGoBack: Bool { true }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationItem.title = "Lesson picker"
    navigationController?.isNavigationBarHidden = false
    let client = services.localCachingClient!
    let items = ReviewItem.readyForLessons(
      assignments: client.getNonExcludedAssignments(), localCachingClient: client)
    var images: [Int64: Image] = [:]
    let subjects = items.compactMap { item -> StudySubject? in
      guard let subject = client.getSubject(id: item.assignment.subjectID) else { return nil }
      if subject.hasRadical, subject.radical.hasCharacterImageFile_p,
        let image = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(subject.id))
      {
        images[subject.id] = Image(uiImage: image).renderingMode(.template)
      }
      return StudySubject(
        id: subject.id, characters: subject.japanese, meaning: subject.primaryMeaning,
        kind: subject.hasRadical ? .radical : subject.hasKanji ? .kanji : .vocabulary,
        level: Int(item.assignment.level))
    }
    rootView = LessonPickerView(
      items: subjects, japaneseFont: TKMStyle.japaneseFontName, image: { images[$0] },
      start: { [weak self] ids in
        guard let self else { return }
        let current = ReviewItem.readyForLessons(
          assignments: client.getNonExcludedAssignments(), localCachingClient: client)
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.assignment.subjectID, $0) })
        guard !ids.isEmpty, ids.allSatisfy({ byID[$0] != nil }) else { throw SelectionChanged() }
        selectedItems = ids.compactMap { byID[$0] }
        perform(segue: StoryboardSegue.LessonPicker.startCustomLessons, sender: self)
      })
  }

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    if case .startCustomLessons = StoryboardSegue.LessonPicker(segue) {
      (segue.destination as! LessonsViewController).setup(services: services, items: selectedItems)
    }
  }
  private struct SelectionChanged: LocalizedError {
    var errorDescription: String? {
      "The available lessons changed. Return to this picker to reload them before starting."
    }
  }
}
