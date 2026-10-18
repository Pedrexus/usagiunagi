import SwiftUI

/// Hosts supply their existing schedule; expanding an hour explains its cumulative counts.
public struct UpcomingReviewsView: View {
  public struct Count: Identifiable, Sendable {
    public let id: String
    public let value: Int
    public init(_ name: String, _ value: Int) {
      id = name
      self.value = value
    }
  }
  public struct Hour: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let total: Int
    public let newReviews: Int
    public let stages: [Count]
    public let subjects: [Count]
    public init(
      id: Int, date: Date, total: Int, newReviews: Int, stages: [Count], subjects: [Count]
    ) {
      self.id = id
      self.date = date
      self.total = total
      self.newReviews = newReviews
      self.stages = stages
      self.subjects = subjects
    }
  }
  private let hours: [Hour]
  public init(hours: [Hour]) { self.hours = hours }

  public var body: some View {
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
