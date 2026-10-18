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

/// Temporary navigation host while the app shell migrates. Settings themselves are SwiftUI.
class ReviewContainerViewController: UIViewController, ReviewViewControllerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private var services: TKMServices!
  var reviewVC: ReviewViewController!

  static func practice(services: TKMServices, subject: TKMSubject) -> ReviewContainerViewController {
    var assignment = TKMAssignment()
    assignment.subjectType = subject.subjectType
    let controller = StoryboardScene.ReviewContainer.initialScene.instantiate()
    controller.setup(services: services, items: [ReviewItem(assignment: assignment, subject: subject)], isPracticeSession: true)
    return controller
  }

  func setup(services: TKMServices, items: [ReviewItem], isPracticeSession: Bool = false) {
    self.services = services
    reviewVC = StoryboardScene.Review.initialScene.instantiate()
    reviewVC.setup(services: services, items: items, showMenuButton: true, showSubjectHistory: true,
                   delegate: self, isPracticeSession: isPracticeSession)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(reviewVC)
    view.addSubview(reviewVC.view)
    reviewVC.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      reviewVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      reviewVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      reviewVC.view.topAnchor.constraint(equalTo: view.topAnchor),
      reviewVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    reviewVC.didMove(toParent: self)
  }

  func allowsCheats(forReviewItem _: ReviewItem) -> Bool { Settings.enableCheats }
  func allowsCustomFonts() -> Bool { true }
  func showsSuccessRate() -> Bool { true }

  func tappedMenuButton(reviewViewController _: ReviewViewController, menuButton _: UIView) {
    reviewVC.prepareForSettings()
    let panel = ReviewSettingsPanel(preferences: ReviewPreferencesAdapter.current,
                                    changed: { [weak self] old, new in
                                      ReviewPreferencesAdapter.apply(new, replacing: old)
                                      self?.view.window?.setInterfaceStyle(Settings.interfaceStyle)
                                      self?.reviewVC.quickSettingsChanged()
                                    }, fonts: { [weak self] in self?.showFonts() },
                                    done: { [weak self] in self?.closeSettings() })
    let host = UIHostingController(rootView: panel)
    host.modalPresentationStyle = .formSheet
    host.presentationController?.delegate = self
    present(host, animated: true)
  }

  private func closeSettings() {
    dismiss(animated: true) { [weak self] in self?.reviewVC.focusAnswerField() }
  }

  func presentationControllerDidDismiss(_: UIPresentationController) {
    reviewVC.focusAnswerField()
  }

  private func showFonts() {
    dismiss(animated: true) { [weak self] in
      guard let self else { return }
      let fonts = StoryboardScene.SelectFonts.initialScene.instantiate()
      fonts.setup(services: self.services)
      self.navigationController?.pushViewController(fonts, animated: true)
    }
  }

  func finishedAllReviewItems(_ reviewViewController: ReviewViewController) {
    reviewViewController.perform(segue: StoryboardSegue.Review.reviewSummary,
                                 sender: reviewViewController)
  }
}
