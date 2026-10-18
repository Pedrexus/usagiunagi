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

/// The dashboard and calculations are shared with native macOS. This adapter only reads the
/// existing cache and routes subject taps into the shared details screen through its navigation adapter.
final class StatisticsViewController: UIHostingController<StudyDashboard?> {
  private let services: TKMServices
  private let notifications = NotificationDispatcher()

  init(services: TKMServices) {
    self.services = services
    super.init(rootView: nil)
    title = "Statistics"
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    for name in [
      Notification.Name.lccUserInfoChanged,
      .lccAvailableItemsChanged,
      .lccPendingItemsChanged,
    ] {
      notifications.add(name: name) { [weak self] _ in
        DispatchQueue.main.async {
          guard self?.viewIfLoaded?.window != nil else { return }
          self?.reloadStatistics()
        }
      }
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadStatistics()
  }

  private func reloadStatistics() {
    guard let client = services.localCachingClient, let user = client.getUserInfo() else { return }
    let subjects = client.getAllSubjects().map { value in
      StudySubject(id: value.id, characters: value.japanese, meaning: value.primaryMeaning,
                   readings: value.readings.map(\.reading),
                   kind: value.hasRadical ? .radical : value.hasKanji ? .kanji : .vocabulary,
                   level: Int(value.level), documentURL: URL(string: value.documentURL))
    }
    let snapshot = StudySnapshot(username: user.username, currentLevel: Int(user.currentLevel),
                                 onVacation: user.hasVacationStartedAt,
                                 assignments: client.getAllAssignments().map(StudyAssignment.init),
                                 statistics: client.getAllReviewStatistics()
                                   .map(StudyAnswerStatistics.init),
                                 levels: client.getAllLevelProgressions().map(StudyLevel.init),
                                 subjects: subjects,
                                 pendingReviews: client.pendingProgressCount,
                                 isSample: Screenshotter.isActive)
    #if DEBUG
      let initialPage: StudyDashboard.Page = ProcessInfo.processInfo.arguments
        .contains("ShowCoverage") ? .coverage : .progress
    #else
      let initialPage: StudyDashboard.Page = .progress
    #endif
    rootView = StudyDashboard(snapshot: snapshot, initialPage: initialPage) { [weak self] id in
      self?.openSubject(id)
    }
  }

  private func openSubject(_ id: Int64) {
    guard let subject = services.localCachingClient.getSubject(id: id) else { return }
    let controller = StoryboardScene.SubjectDetails.initialScene.instantiate()
    controller.setup(services: services, subject: subject)
    navigationController?.pushViewController(controller, animated: true)
  }
}
