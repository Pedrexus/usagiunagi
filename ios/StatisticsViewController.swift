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

import SwiftUI
import UIKit
import WaniKaniAPI

struct StatisticsRow {
  let title: String
  let detail: String
  let symbol: String
  var subjectID: Int64? = nil
}

struct StatisticsSection {
  let title: String
  let footer: String
  let rows: [StatisticsRow]
}

struct StatisticsView: View {
  let sections: [StatisticsSection]
  var openSubject: (Int64) -> Void

  var body: some View {
    List {
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        Section {
          ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
            if let id = row.subjectID {
              Button { openSubject(id) } label: { content(row) }
                .buttonStyle(.plain)
            } else {
              content(row)
            }
          }
        } header: {
          Text(section.title).textCase(nil)
        } footer: {
          Text(section.footer)
        }
      }
    }
    .listStyle(.insetGrouped)
    .accessibilityIdentifier("Statistics")
  }

  private func content(_ row: StatisticsRow) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: row.symbol).foregroundStyle(.secondary).frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(row.title).font(.body).foregroundStyle(.primary)
        Text(row.detail).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if row.subjectID != nil {
        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

// Temporary bridge into the existing UIKit tab shell. The screen itself is SwiftUI.
final class StatisticsViewController: UIHostingController<StatisticsView> {
  private let services: TKMServices
  private var sections = [StatisticsSection]()
  private let notifications = NotificationDispatcher()

  init(services: TKMServices) {
    self.services = services
    super.init(rootView: StatisticsView(sections: [], openSubject: { _ in }))
    title = "Statistics"
    tabBarItem = UITabBarItem(title: "Stats", image: UIImage(systemName: "chart.bar.xaxis"), tag: 2)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    for name in [
      Notification.Name.lccUserInfoChanged,
      .lccAvailableItemsChanged,
      .lccPendingItemsChanged,
    ] {
      notifications.add(name: name) { [weak self] _ in
        DispatchQueue.main.async { self?.reloadStatistics() }
      }
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadStatistics()
  }

  func reloadStatistics() {
    guard isViewLoaded, let client = services.localCachingClient,
          let user = client.getUserInfo() else { return }
    let stats = StudyStatistics(assignments: client.getAllAssignments(),
                                statistics: client.getAllReviewStatistics(),
                                levels: client.getAllLevelProgressions(),
                                currentLevel: Int(user.currentLevel),
                                onVacation: user.hasVacationStartedAt)
    let pending = client.pendingProgressCount
    sections =
      [StatisticsSection(title: Screenshotter.isActive ? "Statistics · Sample data" : "Statistics",
                         footer: "Synced lifetime answers, not a retention estimate. Pull to refresh on Home to sync." +
                           (pending > 0 ? " \(pending) pending uploads are excluded." : ""),
                         rows: [
                           StatisticsRow(title: "Reading accuracy",
                                         detail: accuracy(stats.reading),
                                         symbol: "character.book.closed"),
                           StatisticsRow(title: "Meaning accuracy",
                                         detail: accuracy(stats.meaning),
                                         symbol: "text.book.closed"),
                         ])]

    var paceRows = [StatisticsRow]()
    if let pace = stats.pace {
      paceRows.append(StatisticsRow(title: "Typical level pace",
                                    detail: String(format: "%.1f days · median of %d completed levels",
                                                   pace.medianDays, pace.sampleCount),
                                    symbol: "speedometer"))
      paceRows.append(StatisticsRow(title: "Recent pace range",
                                    detail: String(format: "%.1f–%.1f days per level · middle half of your sample",
                                                   pace.lowerDays, pace.upperDays),
                                    symbol: "arrow.left.and.right"))
      if pending == 0, let range = pace.nextLevelRange {
        let date = DateFormatter()
        date.dateStyle = .medium
        paceRows.append(StatisticsRow(title: "Level \(user.currentLevel + 1) scenario",
                                      detail: "\(date.string(from: range.lowerBound)) – \(date.string(from: range.upperBound))",
                                      symbol: "calendar"))
      } else {
        let reason = user.hasVacationStartedAt ? "Paused during vacation." :
          user.currentLevel >= 60 ? "You have reached level 60." :
          pending > 0 ? "Sync pending reviews first." :
          "Your current level is outside the early part of this pace range, or its start is unavailable. No date estimate shown."
        paceRows.append(StatisticsRow(title: "Next level estimate unavailable", detail: reason,
                                      symbol: "calendar.badge.exclamationmark"))
      }
    } else {
      paceRows.append(StatisticsRow(title: "Building your pace history",
                                    detail: "Needs at least 3 completed levels from level 3 onward, after your latest recorded reset.",
                                    symbol: "clock"))
    }
    sections.append(StatisticsSection(title: "Level pace",
                                      footer: "Based on recent levels, including time off. Dates assume a similar pace; lesson choices, mistakes and breaks can change the outcome.",
                                      rows: paceRows))

    if user.hasVacationStartedAt || pending > 0 {
      sections.append(StatisticsSection(title: "Scheduled reviews",
                                        footer: "Only each item's next scheduled review is counted. New lessons and repeat reviews are not forecast.",
                                        rows: [StatisticsRow(title: user
                                            .hasVacationStartedAt ? "Vacation mode" :
                                            "Schedule awaiting sync",
                                          detail: user
                                            .hasVacationStartedAt ?
                                            "Review dates are paused." :
                                            "Sync your pending reviews to update these dates.",
                                          symbol: "pause.circle")]))
    } else {
      let date = DateFormatter()
      date.dateFormat = "EEE, MMM d"
      var rows = [StatisticsRow(title: "Due now", detail: "\(stats.dueNow) items", symbol: "tray")]
      rows += stats.scheduledDays.map { StatisticsRow(title: date.string(from: $0.date),
                                                      detail: "\($0.count) scheduled items",
                                                      symbol: "calendar") }
      sections.append(StatisticsSection(title: "Next 7 days",
                                        footer: "Each item's next review, in local time. Repeat reviews, new lessons and future mistakes will add work.",
                                        rows: rows))
    }

    let focusRows = stats.focus.prefix(5).compactMap { item -> StatisticsRow? in
      guard let subject = client.getSubject(id: item.subjectID) else { return nil }
      return StatisticsRow(title: subject.japanese.isEmpty ? subject.primaryMeaning : subject
        .japanese,
        detail: "\(item.reading ? "Reading" : "Meaning"): \(item.incorrect) incorrect / \(item.attempts) answers · current correct streak \(item.streak)",
        symbol: "scope", subjectID: item.subjectID)
    }
    sections.append(StatisticsSection(title: "Focus next",
                                      footer: "Prioritizes repeated errors, with less weight after a correct streak. Requires at least 5 answers and 2 errors. Tap to revisit readings and mnemonics.",
                                      rows: focusRows
                                        .isEmpty ?
                                        [StatisticsRow(title: "No recurring trouble items yet",
                                                       detail: "Keep reviewing to build enough evidence.",
                                                       symbol: "checkmark.circle")] :
                                        focusRows))
    rootView = StatisticsView(sections: sections) { [weak self] id in
      self?.openSubject(id)
    }
  }

  private func accuracy(_ accuracy: StudyStatistics.Accuracy) -> String {
    guard let fraction = accuracy.fraction else { return "Not enough answer history" }
    return String(format: "%.1f%% · %d correct / %d answers", fraction * 100, accuracy.correct,
                  accuracy.attempts)
  }

  private func openSubject(_ id: Int64) {
    guard let subject = services.localCachingClient.getSubject(id: id) else { return }
    let controller = StoryboardScene.SubjectDetails.initialScene.instantiate()
    controller.setup(services: services, subject: subject)
    navigationController?.pushViewController(controller, animated: true)
  }
}
