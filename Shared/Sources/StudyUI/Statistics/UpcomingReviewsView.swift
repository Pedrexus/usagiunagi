import SwiftUI

/// Hosts supply their existing schedule; expanding an hour explains its cumulative counts.
struct UpcomingReviewsView: View {
  struct Count: Identifiable, Sendable {
    let id: String
    let value: Int
  }
  struct Hour: Identifiable, Sendable {
    let id: Int
    let date: Date
    let total: Int
    let newReviews: Int
    let stages: [Count]
    let subjects: [Count]
  }
  let hours: [Hour]

  var body: some View {
    List {
      Section {
        ForEach(hours) { hour in
          DisclosureGroup {
            ForEach(hour.stages) { count in
              LabeledContent(count.id, value: count.value.formatted())
            }
            ForEach(hour.subjects) { count in
              LabeledContent(count.id, value: count.value.formatted())
            }
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(hour.date, format: .dateTime.day().month(.abbreviated).hour())
                .font(.headline)
              Text("\(hour.total) reviews · +\(hour.newReviews) this hour")
                .foregroundStyle(.secondary)
            }
          }.accessibilityIdentifier("schedule.hour.\(hour.id)")
        }
      } footer: {
        Text(
          "Totals include all reviews available by that hour. Expand an hour for totals by SRS stage and subject type. Repeat reviews, mistakes and new lessons add work beyond this schedule."
        )
      }
    }.accessibilityIdentifier("upcomingReviews")
  }
}
