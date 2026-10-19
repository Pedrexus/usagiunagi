// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore
import WaniKaniAPI

enum HomeTiming {
  static func rows(services: TKMServices, assignments: [TKMAssignment], showMinutes: Bool)
    -> [HomeDashboardData.Metric]
  {
    guard let client = services.localCachingClient, let user = client.getUserInfo() else {
      return []
    }
    var profile = StudyAccountProfile(username: user.username)
    profile.level = Int(user.currentLevel)
    profile.maxLevelGranted = Int(user.maxLevelGrantedBySubscription)
    profile.vacationStartedAt = user.hasVacationStartedAt ? Int64(user.vacationStartedAt) : nil
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    source.levels = client.getAllLevelProgressions().map { value in
      var level = CatalogLevelProgression(id: value.id)
      level.level = Int(value.level)
      level.unlockedAt = value.hasUnlockedAt ? Int64(value.unlockedAt) : nil
      level.passedAt = value.hasPassedAt ? Int64(value.passedAt) : nil
      level.abandonedAt = value.hasAbandonedAt ? Int64(value.abandonedAt) : nil
      return level
    }
    let subjects = assignments.compactMap { assignment in
      client.getSubject(id: assignment.subjectID).flatMap {
        try? LegacyStudyImporter.catalogSubject($0)
      }
    }
    let items = assignments.filter(\.hasSrsStageNumber).map { value in
      var item = CatalogAssignment(
        id: value.id, subjectID: value.subjectID,
        kind: value.subjectType == .radical
          ? .radical : value.subjectType == .kanji ? .kanji : .vocabulary)
      item.level = Int(value.level)
      item.srsStage = Int(value.srsStageNumber)
      item.availableAt = value.hasAvailableAt ? Int64(value.availableAt) : nil
      item.startedAt = value.hasStartedAt ? Int64(value.startedAt) : nil
      item.passedAt = value.hasPassedAt ? Int64(value.passedAt) : nil
      return item
    }
    let available = StudyAvailability(
      account: .init(legacy: source), subjects: subjects, assignments: items)
    return (try? available.homeTiming(showMinutes: showMinutes)) ?? []
  }
}
