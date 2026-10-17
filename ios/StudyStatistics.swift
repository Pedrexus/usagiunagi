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
import WaniKaniAPI

/// Pure calculations from synced WaniKani data. No changes to scheduling or grading.
struct StudyStatistics {
  struct Accuracy {
    let correct: Int
    let incorrect: Int
    var attempts: Int { correct + incorrect }
    var fraction: Double? { attempts > 0 ? Double(correct) / Double(attempts) : nil }
  }

  struct FocusItem {
    let subjectID: Int64
    let reading: Bool
    let incorrect: Int
    let attempts: Int
    let streak: Int
    let score: Double
  }

  struct Pace {
    let sampleCount: Int
    let lowerDays: Double
    let medianDays: Double
    let upperDays: Double
    let nextLevelRange: ClosedRange<Date>?
  }

  let meaning: Accuracy
  let reading: Accuracy
  let dueNow: Int
  /// One next review per assignment, grouped into the next seven local calendar days.
  let scheduledDays: [(date: Date, count: Int)]
  let focus: [FocusItem]
  let pace: Pace?

  init(assignments: [TKMAssignment], statistics: [TKMReviewStatistic], levels: [TKMLevel],
       currentLevel: Int, onVacation: Bool, now: Date = Date(), calendar: Calendar = .current) {
    let visible = statistics.filter { !$0.hidden }
    meaning = Accuracy(correct: visible.reduce(0) { $0 + Int($1.meaningCorrect) },
                       incorrect: visible.reduce(0) { $0 + Int($1.meaningIncorrect) })
    reading = Accuracy(correct: visible.reduce(0) { $0 + Int($1.readingCorrect) },
                       incorrect: visible.reduce(0) { $0 + Int($1.readingIncorrect) })
    // Deduplicate defensively, including old sample-data fixtures.
    let active = Dictionary(assignments.filter { $0.srsStageNumber > 0 && $0.srsStageNumber < 9 }
      .map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
    let dates = active.values.filter { $0.hasAvailableAt && $0.availableAt > 0 }
      .map { Date(timeIntervalSince1970: Double($0.availableAt)) }
    dueNow = dates.filter { $0 <= now }.count
    scheduledDays = (0 ..< 7).map { offset in
      let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
      let end = calendar.date(byAdding: .day, value: 1, to: start)!
      return (start, dates.filter { $0 > now && $0 >= start && $0 < end }.count)
    }
    focus = visible.filter { active[$0.subjectID] != nil }.compactMap { stat in
      let meaning = Self.focusItem(stat, reading: false)
      let reading = stat.type == .radical ? nil : Self.focusItem(stat, reading: true)
      return [meaning, reading].compactMap { $0 }.max { $0.score < $1.score }
    }.sorted { $0.score == $1.score ? $0.subjectID < $1.subjectID : $0.score > $1.score }
    pace = Self.calculatePace(levels, currentLevel: currentLevel, onVacation: onVacation, now: now)
  }

  private static func focusItem(_ stat: TKMReviewStatistic, reading: Bool) -> FocusItem? {
    let incorrect = Int(reading ? stat.readingIncorrect : stat.meaningIncorrect)
    let correct = Int(reading ? stat.readingCorrect : stat.meaningCorrect)
    let streak = max(0, Int(reading ? stat.readingCurrentStreak : stat.meaningCurrentStreak))
    let total = correct + incorrect
    guard total >= 5, incorrect >= 2 else { return nil }
    // Smoothed error rate discounted by recovery streak. A prioritization heuristic, not a
    // probability.
    let score = (Double(incorrect) + 1) / (Double(total) + 2) / sqrt(Double(streak) + 1)
    return FocusItem(subjectID: stat.subjectID, reading: reading, incorrect: incorrect,
                     attempts: total, streak: streak, score: score)
  }

  private static func calculatePace(_ levels: [TKMLevel], currentLevel: Int,
                                    onVacation: Bool, now: Date) -> Pace? {
    let reset = levels.map { $0.abandonedAt }.max() ?? 0
    // Keep only the latest attempt at each level; do not carry pre-reset pace into a new run.
    let latest = Dictionary(levels.map { ($0.level, $0) }, uniquingKeysWith: {
      $0.unlockedAt > $1.unlockedAt ? $0 : $1
    })
    let completed = latest.values.filter {
      $0.level >= 3 && $0.level < currentLevel && !$0.hasAbandonedAt &&
        $0.hasUnlockedAt && $0.unlockedAt >= reset && $0.passedAt > $0.unlockedAt &&
        Double($0.passedAt) <= now.timeIntervalSince1970
    }.sorted { $0.passedAt > $1.passedAt }.prefix(8)
    guard completed.count >= 3 else { return nil }
    let durations = completed.map { (Double($0.passedAt) - Double($0.unlockedAt)) / 86400 }.sorted()
    let low = quantile(durations, 0.25), median = quantile(durations, 0.5),
        high = quantile(durations,
                        0.75)
    var range: ClosedRange<Date>?
    if !onVacation, currentLevel < 60, let current = latest[Int32(currentLevel)],
       !current.hasPassedAt, !current.hasAbandonedAt, current.hasUnlockedAt,
       current.unlockedAt >= reset, current.unlockedAt > 0 {
      let start = Date(timeIntervalSince1970: Double(current.unlockedAt))
      let elapsed = now.timeIntervalSince(start) / 86400
      // Avoid rolling an overdue prediction forward every day or presenting a past date.
      if elapsed >= 0, elapsed < low {
        range = start.addingTimeInterval(low * 86400) ... start.addingTimeInterval(high * 86400)
      }
    }
    return Pace(sampleCount: completed.count, lowerDays: low, medianDays: median, upperDays: high,
                nextLevelRange: range)
  }

  private static func quantile(_ sorted: [Double], _ p: Double) -> Double {
    let position = Double(sorted.count - 1) * p
    let lower = Int(position), upper = min(lower + 1, sorted.count - 1)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
  }
}
