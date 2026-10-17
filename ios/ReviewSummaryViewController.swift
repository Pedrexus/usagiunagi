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

/// Adapts the existing repository/navigation to the shared SwiftUI results screen.
final class ReviewSummaryViewController: UIHostingController<SessionSummaryView?> {
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }

  func setup(services: TKMServices, items: [ReviewItem]) {
    var subjects: [Int: TKMSubject] = [:]
    var entries: [StudySessionSummary.Entry] = []
    var images: [Int: Image] = [:]
    for (index, item) in items.enumerated() {
      let subject = item.subject ?? services.localCachingClient.getSubject(id: item.assignment.subjectID)
      subjects[index] = subject
      let summary = subject.map {
        StudySubject(id: $0.id, characters: $0.japanese,
                     meaning: $0.commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic),
                     readings: ($0.hasKanji ? $0.primaryReadings : $0.readings).map(\.reading),
                     kind: $0.hasRadical ? .radical : $0.hasKanji ? .kanji : .vocabulary,
                     level: Int($0.level))
      }
      if let subject, subject.hasRadical, subject.radical.hasCharacterImageFile_p,
         let image = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(subject.id)) {
        images[index] = Image(uiImage: image).renderingMode(.template)
      }
      entries.append(.init(id: index, subject: summary, level: Int(item.assignment.level),
                           meaningWrong: item.answer.meaningWrong, readingWrong: item.answer.readingWrong))
    }
    let summary = StudySessionSummary(entries: entries,
                                     currentLevel: services.localCachingClient.getUserInfo().map { Int($0.level) })
    rootView = SessionSummaryView(summary: summary, japaneseFont: TKMStyle.japaneseFontName,
                                 image: { images[$0] }) { [weak self] index in
      guard let self, let subject = subjects[index] else { return }
      let vc = StoryboardScene.SubjectDetails.initialScene.instantiate()
      vc.setup(services: services, subject: subject, showHints: false, hideBackButton: false, index: 0)
      navigationController?.pushViewController(vc, animated: true)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }
  @IBAction private func doneClicked() { navigationController?.popToRootViewController(animated: true) }
  override var canBecomeFirstResponder: Bool { true }
  override var keyCommands: [UIKeyCommand]? {
    [UIKeyCommand(title: "Dismiss review session results", action: #selector(doneClicked), input: "\r")]
  }
}
