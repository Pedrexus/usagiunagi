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

final class UpcomingReviewsViewController: UIHostingController<UpcomingReviewsView?>,
  TKMViewController
{
  private var services: TKMServices!
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices) { self.services = services }
  var canSwipeToGoBack: Bool { true }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    let now = Date()
    let stages: [SRSStageCategory] = [.apprentice, .guru, .master, .enlightened]
    let types: [(TKMSubject.TypeEnum, String)] = [
      (.radical, "Radical"), (.kanji, "Kanji"), (.vocabulary, "Vocabulary"),
    ]
    var cumulative = ReviewComposition()
    var hours: [UpcomingReviewsView.Hour] = []
    for (hour, composition) in services.localCachingClient.availableSubjects.reviewComposition
      .enumerated()
    {
      cumulative = cumulative + composition
      guard hour == 0 || composition.availableReviews > 0 else { continue }
      hours.append(
        .init(
          id: hour, date: now.addingTimeInterval(TimeInterval(hour * 3600)),
          total: cumulative.availableReviews, newReviews: composition.availableReviews,
          stages: stages.map { .init($0.description, cumulative.countByCategory[$0, default: 0]) },
          subjects: types.map { .init($0.1, cumulative.countByType[$0.0, default: 0]) }))
    }
    rootView = UpcomingReviewsView(hours: hours)
  }
}
