import StudyCore
import SwiftUI

struct SubjectProgressView: View {
  let assignment: CatalogAssignment
  let level: Int
  var body: some View {
    GroupBox("Stats") {
      VStack(spacing: 10) {
        LabeledContent("WaniKani level", value: String(level))
        if let started = assignment.startedAt {
          if let stage = StudySRSStage(rawValue: assignment.srsStage) {
            LabeledContent("SRS stage", value: stage.name)
          }
          date("Started", started)
          if let next = assignment.availableAt { date("Next review", next) }
          if let passed = assignment.passedAt { date("Passed", passed) }
          if let burned = assignment.burnedAt { date("Burned", burned) }
        }
      }
    }.accessibilityIdentifier("subject.statistics")
  }
  private func date(_ title: String, _ timestamp: Int64) -> some View {
    LabeledContent(
      title,
      value: Date(timeIntervalSince1970: Double(timestamp)).formatted(
        date: .abbreviated, time: .shortened))
  }
}
