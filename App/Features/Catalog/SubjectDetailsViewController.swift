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

import StudyUI
import SwiftUI
import WaniKaniAPI

final class SubjectDetailsViewController: UIHostingController<SubjectDetailsPage?>, SubjectDelegate,
  TKMViewController
{
  private var services: TKMServices!
  private var subject: TKMSubject!
  private var hidesBack = false
  private var model: LegacySubjectDetailsModel!
  @objc private(set) var index = 0
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(
    services: TKMServices, subject: TKMSubject,
    hideBackButton: Bool = false, index: Int = 0
  ) {
    self.services = services
    self.subject = subject
    self.hidesBack = hideBackButton
    self.index = index
  }
  var canSwipeToGoBack: Bool { true }
  override func viewDidLoad() {
    super.viewDidLoad()
    model = LegacySubjectDetailsModel(services: services, delegate: self)
    rootView = SubjectDetailsPage(
      model: model, showsHeader: true,
      back: hidesBack
        ? nil : { [weak self] in self?.navigationController?.popViewController(animated: true) })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
    model.update(
      subject: subject, assignment: services.localCachingClient.getAssignment(subjectId: subject.id)
    )
  }
  func didTapSubject(_ subject: TKMSubject) {
    let controller = StoryboardScene.SubjectDetails.initialScene.instantiate()
    controller.setup(services: services, subject: subject)
    navigationController?.pushViewController(controller, animated: true)
  }
  override var canBecomeFirstResponder: Bool { true }
  override var keyCommands: [UIKeyCommand]? {
    [
      UIKeyCommand(
        title: "Show all information", action: #selector(showAllInformation), input: " "),
      UIKeyCommand(title: "Play reading", action: #selector(playAudio), input: "j"),
      UIKeyCommand(title: "Back", action: #selector(back), input: UIKeyCommand.inputLeftArrow),
    ]
  }
  @objc private func back() { navigationController?.popViewController(animated: true) }
  @objc func showAllInformation() { model.showAllFields() }
  @objc func playAudio() { model.playAudio() }
}
