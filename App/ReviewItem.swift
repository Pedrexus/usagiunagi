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

typealias TaskType = StudyQuestionKind

class ReviewItem: NSObject {
  private class func filterReadyItems(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient,
    _ isIncluded: (TKMAssignment) -> Bool
  ) -> [ReviewItem] {
    var ret = [ReviewItem]()
    guard localCachingClient.getUserInfo() != nil else {
      return ret
    }

    let showKanaOnlyVocab = Settings.showKanaOnlyVocab
    for assignment in assignments {
      if !localCachingClient.isValid(subjectId: assignment.subjectID) {
        continue
      }
      if !showKanaOnlyVocab, assignment.isKanaOnlyVocab {
        continue
      }
      if !isIncluded(assignment) {
        continue
      }
      ret.append(ReviewItem(assignment: assignment))
    }
    return ret
  }

  class func readyForReview(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  ) -> [ReviewItem] {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.isReviewStage && assignment.availableAtDate.timeIntervalSinceNow < 0
    }
  }

  class func readyForRecentReview(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  ) -> [ReviewItem] {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.isReviewStage
    }
  }

  class func readyForAlreadyPassedApprenticeReview(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  )
    -> [ReviewItem]
  {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.hasPassedAt && assignment.srsStage < .guru1
    }
  }

  class func readyForLeechReview(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  )
    -> [ReviewItem]
  {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.hasPassedAt && !assignment.hasBurnedAt
    }
  }

  class func readyForBurnedReview(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  ) -> [ReviewItem] {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.isBurned
    }
  }

  class func readyForLessons(
    assignments: [TKMAssignment],
    localCachingClient: LocalCachingClient
  ) -> [ReviewItem] {
    filterReadyItems(
      assignments: assignments,
      localCachingClient: localCachingClient
    ) { assignment -> Bool in
      assignment.isLessonStage
    }
  }

  let assignment: TKMAssignment
  let subject: TKMSubject?

  var answeredReading = false
  var answeredMeaning = false
  var answer = TKMProgress()

  init(assignment: TKMAssignment, subject: TKMSubject? = nil) {
    self.assignment = assignment
    self.subject = subject
    answer.assignment = assignment
    answer.isLesson = assignment.isLessonStage
  }

  var lessonSortKey: StudyLessonPreferences.SortKey {
    let kind: SubjectKind =
      switch assignment.subjectType {
      case .radical: .radical
      case .kanji: .kanji
      default: .vocabulary
      }
    return (level: Int(assignment.level), kind: kind, subjectID: assignment.subjectID)
  }
}
