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

/// Teaching is SwiftUI; the quiz host retains the existing input adapter and durable writer.
final class LessonsViewController: UIHostingController<LessonFlowView<LessonPage>?>,
  ReviewViewControllerDelegate, SubjectDelegate
{
  private var services: TKMServices!
  private var items: [ReviewItem] = []
  private var reviewViewController: ReviewViewController?
  private var teachingModels: [Int: LegacySubjectDetailsModel] = [:]
  private weak var teachingModel: LegacySubjectDetailsModel?
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices, items: [ReviewItem]) {
    self.services = services
    self.items = items
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    var images: [Int64: Image] = [:]
    let subjects = items.map { item in
      let subject = services.localCachingClient.getSubject(id: item.assignment.subjectID)
      if let subject, subject.hasRadical, subject.radical.hasCharacterImageFile_p,
        let image = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(subject.id))
      {
        images[subject.id] = Image(uiImage: image).renderingMode(.template)
      }
      return StudySubject(
        id: item.assignment.subjectID, characters: subject?.japanese ?? "",
        meaning: subject?.primaryMeaning ?? "Subject \(item.assignment.subjectID)",
        kind: subject?.hasRadical == true
          ? .radical : subject?.hasVocabulary == true ? .vocabulary : .kanji)
    }
    rootView = LessonFlowView(
      subjects: subjects, japaneseFont: TKMStyle.japaneseFontName, image: { images[$0] },
      back: { [weak self] in
        self?.navigationController?.popViewController(animated: true)
      }, playAudio: { [weak self] in self?.teachingModel?.playAudio() },
      page: { [weak self] index in
        self?.makePage(index) ?? .unavailable
      })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
    SiriShortcutHelper.shared.attachShortcutActivity(self, type: .lessons)
  }
  private func makePage(_ index: Int) -> LessonPage {
    if index == items.count {
      if let reviewViewController { return .quiz(reviewViewController) }
      let controller = StoryboardScene.Review.initialScene.instantiate()
      controller.setup(
        services: services, items: items, showMenuButton: false,
        showSubjectHistory: false, delegate: self)
      reviewViewController = controller
      return .quiz(controller)
    }
    guard items.indices.contains(index),
      let subject = services.localCachingClient.getSubject(id: items[index].assignment.subjectID)
    else {
      return .unavailable
    }
    let model =
      teachingModels[index] ?? LegacySubjectDetailsModel(services: services, delegate: self)
    if teachingModels[index] == nil {
      model.update(subject: subject, assignment: items[index].assignment)
    }
    teachingModels[index] = model
    teachingModel = model
    return .teaching(model)
  }
  func didTapSubject(_ subject: TKMSubject) {
    let controller = StoryboardScene.SubjectDetails.initialScene.instantiate()
    controller.setup(services: services, subject: subject)
    navigationController?.pushViewController(controller, animated: true)
  }
  func allowsCheats(forReviewItem _: ReviewItem) -> Bool { false }
  func openPracticeReview(_ subject: TKMSubject) {
    guard FeatureFlags.showSubjectDeveloperOptions else { return }
    navigationController?.pushViewController(
      ReviewContainerViewController.practice(services: services, subject: subject), animated: true)
  }
  func allowsCustomFonts() -> Bool { false }
  func showsSuccessRate() -> Bool { false }
  func finishedAllReviewItems(_: ReviewViewController) {
    navigationController?.popToRootViewController(animated: true)
  }
}

enum LessonPage: View {
  case teaching(LegacySubjectDetailsModel)
  case quiz(ReviewViewController)
  case unavailable
  var body: some View {
    switch self {
    case .teaching(let model):
      SubjectDetailsPage(model: model, showsHeader: true).onAppear { model.reload() }
    case .quiz(let controller): LessonQuizView(controller: controller)
    case .unavailable:
      ContentUnavailableView(
        "Study content unavailable", systemImage: "book.closed",
        description: Text("Return and refresh your account before continuing."))
    }
  }
}

private struct LessonQuizView: UIViewControllerRepresentable {
  let controller: ReviewViewController
  func makeUIViewController(context: Context) -> UIViewController { controller }
  func updateUIViewController(_: UIViewController, context: Context) {}
  static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
    controller.view.endEditing(true)
  }
}
