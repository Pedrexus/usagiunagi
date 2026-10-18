// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import WaniKaniAPI

enum HomeTiming {
  static func levelRemaining(
    services: TKMServices,
    currentLevelAssignments: [TKMAssignment]
  )
    -> (finish: Date, isEstimate: Bool)
  {
    var radicalDates = [Date]()
    var guruDates = [Date]()
    var subjects = [TKMSubject]()

    for assignment in currentLevelAssignments {
      if assignment.subjectType != .radical {
        continue
      }
      guard let subject = services.localCachingClient.getSubject(id: assignment.subjectID),
        let guruDate = assignment.guruDate(subject: subject)
      else {
        continue
      }
      radicalDates.append(guruDate)
    }
    radicalDates.sort()
    let lastRadicalGuruTime = max(radicalDates.last?.timeIntervalSinceNow ?? 0, 0)

    for assignment in currentLevelAssignments {
      if assignment.subjectType != .kanji {
        continue
      }
      let subject = services.localCachingClient.getSubject(id: assignment.subjectID)
      if let subject = subject { subjects.append(subject) }
      if assignment.isLocked {
        // This kanji is locked, but it might not be essential for level-up
        guruDates.append(Date.distantFuture)
        continue
      }
      if let subject = subject, let guruDate = assignment.guruDate(subject: subject) {
        guruDates.append(guruDate)
      }
    }

    // Sort the list of dates and remove the most distant 10%.
    guruDates = Array(guruDates.sorted().dropLast(Int(Double(guruDates.count) * 0.1)))
    subjects = Array(
      subjects.sorted { $0.level > $1.level }
        .dropLast(Int(Double(subjects.count) * 0.1)))

    if let lastGuruDate = guruDates.last, let lastSubject = subjects.last {
      if lastGuruDate == Date.distantFuture {
        // There is still a locked kanji needed for level-up, so we don't know how long
        // the user will take to level up. Use their average level time, minus the time
        // they've spent at this level so far, as an estimate.
        var average = averageRemainingLevelTime(services.localCachingClient!)
        // But ensure it can't be less than the time it would take to get a fresh item
        // to Guru, if they've spent longer at the current level than the average.
        average = max(
          average,
          SRSStage.apprentice1.minimumTimeUntilGuru(lastSubject) + lastRadicalGuruTime)
        return (Date(timeIntervalSinceNow: average), isEstimate: true)
      } else {
        return (lastGuruDate, isEstimate: false)
      }
    }

    return (Date(), false)
  }

  private static func averageRemainingLevelTime(_ lcc: LocalCachingClient) -> TimeInterval {
    var timeSpentAtEachLevel = [TimeInterval]()
    for level in lcc.getAllLevelProgressions() {
      if level.timeSpentCurrent > 0 {
        timeSpentAtEachLevel.append(level.timeSpentCurrent)
      }
    }
    if timeSpentAtEachLevel.isEmpty {
      return 0
    }

    let currentLevelTime = timeSpentAtEachLevel.last!
    let lastPassIndex = timeSpentAtEachLevel.count - 1

    // Use the median 50% to calculate the average time
    let lowerIndex = lastPassIndex / 4 + (lastPassIndex % 4 == 3 ? 1 : 0)
    let upperIndex = lastPassIndex * 3 / 4 + (lastPassIndex == 1 ? 1 : 0)

    let medianPassRange = timeSpentAtEachLevel[lowerIndex...upperIndex]
    let averageTime = medianPassRange.reduce(0, +) / Double(medianPassRange.count)
    let remainingTime = averageTime - currentLevelTime

    return remainingTime
  }

  static func intervalString(_ date: Date, showMinutes: Bool = false) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = DateComponentsFormatter.UnitsStyle.abbreviated

    let componentsBitMask: Set = [
      Calendar.Component.day, Calendar.Component.hour,
      Calendar.Component.minute,
    ]
    var components = Calendar.current.dateComponents(componentsBitMask, from: Date(), to: date)

    // Only show minutes after there are no hours left.
    if !showMinutes, let hour = components.hour, hour > 0 {
      components.minute = 0
    }

    return formatter.string(from: components)!
  }

  static func nextReview(
    services: TKMServices,
    currentLevelAssignments: [TKMAssignment]
  ) -> Date {
    var guruDates = [Date]()
    var reviewDates = [Date]()

    for assignment in currentLevelAssignments {
      if assignment.subjectType != .kanji {
        continue
      }
      if !assignment.hasAvailableAt {
        // This kanji is locked, but it might not be essential for level-up
        guruDates.append(Date.distantFuture)
        continue
      }
      guard let subject = services.localCachingClient.getSubject(id: assignment.subjectID),
        let guruDate = assignment.guruDate(subject: subject)
      else {
        continue
      }
      guruDates.append(guruDate)
    }

    // Sort the list of dates and remove the most distant 10%.
    guruDates = Array(guruDates.sorted().dropLast(Int(Double(guruDates.count) * 0.1)))
    let levelKanjiUnlocked = guruDates.last != nil ? (guruDates.last! != Date.distantFuture) : true

    for assignment in currentLevelAssignments {
      if assignment.hasPassedAt
        || assignment
          .subjectType == .vocabulary
        || (levelKanjiUnlocked && assignment.subjectType == .radical)
      {
        continue
      }
      if let reviewDate = assignment.reviewDate {
        if !assignment.isLessonStage {
          reviewDates.append(reviewDate)
        }
      }
    }

    // Sort the list of dates
    reviewDates.sort()

    if let firstReviewDate = reviewDates.first {
      return firstReviewDate
    }
    return Date.distantFuture
  }

}
