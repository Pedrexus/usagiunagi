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
import WaniKaniAPI

// Keep the legacy protobuf boundary out of the shared Swift 6 implementation.
typealias StudyStatistics = StudyMetrics

extension StudyMetrics {
  init(assignments: [TKMAssignment], statistics: [TKMReviewStatistic], levels: [TKMLevel],
       currentLevel: Int, onVacation: Bool, now: Date = Date(), calendar: Calendar = .current) {
    self.init(assignments: assignments.map(StudyAssignment.init),
              statistics: statistics.map(StudyAnswerStatistics.init),
              levels: levels.map(StudyLevel.init),
              currentLevel: currentLevel, onVacation: onVacation, now: now, calendar: calendar)
  }
}

extension StudyAssignment {
  init(_ value: TKMAssignment) {
    self.init(subjectID: value.subjectID, srsStageNumber: Int(value.srsStageNumber),
              availableAt: Int64(value.availableAt))
  }
}

extension StudyAnswerStatistics {
  init(_ value: TKMReviewStatistic) {
    self.init(subjectID: value.subjectID,
              type: value.type == .radical ? .radical : value.type == .kanji ? .kanji : .vocabulary,
              meaningCorrect: Int(value.meaningCorrect),
              meaningIncorrect: Int(value.meaningIncorrect),
              meaningCurrentStreak: Int(value.meaningCurrentStreak),
              readingCorrect: Int(value.readingCorrect),
              readingIncorrect: Int(value.readingIncorrect),
              readingCurrentStreak: Int(value.readingCurrentStreak), hidden: value.hidden)
  }
}

extension StudyLevel {
  init(_ value: TKMLevel) {
    self.init(level: value.level, unlockedAt: Int64(value.unlockedAt),
              passedAt: Int64(value.passedAt), abandonedAt: Int64(value.abandonedAt))
  }
}
