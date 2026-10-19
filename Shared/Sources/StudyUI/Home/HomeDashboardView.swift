import Charts
import StudyCore
import SwiftUI

public enum HomeAction: Hashable, Sendable {
  case reviews, lessons, chooseLessons, apprenticePractice, recentLessons, recentMistakes, leeches,
    burned, forecast, excluded
  case catalog(Int)
  case remaining(Int)
  case stage(Int)
}

public struct HomeDashboardView: View {
  let data: HomeDashboardData
  let action: (HomeAction) -> Void
  let refresh: () async -> Void
  let resume: (() -> Void)?
  @Environment(\.isEnabled) private var isEnabled
  private let stageColors: [Color] = [
    StudyPalette.kanji, StudyPalette.vocabulary,
    Color(red: 47.0 / 255, green: 85.0 / 255, blue: 181.0 / 255),
    Color(red: 47.0 / 255, green: 127.0 / 255, blue: 181.0 / 255), .primary,
  ]
  public init(
    data: HomeDashboardData, action: @escaping (HomeAction) -> Void,
    refresh: @escaping () async -> Void, resume: (() -> Void)? = nil
  ) {
    self.data = data
    self.action = action
    self.refresh = refresh
    self.resume = resume
  }
  public var body: some View {
    List {
      if let notice = data.notice {
        Text(notice).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier(
          "home.notice")
      }
      if let title = data.resumeTitle, let resume {
        Button(title, systemImage: "play.circle", action: resume)
          .buttonStyle(.borderedProminent).accessibilityIdentifier("home.resume")
      }
      if !data.onVacation {
        Section {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
              lessonCard.frame(minWidth: 230)
              reviewCard.frame(minWidth: 230)
            }
            VStack(spacing: 12) {
              lessonCard
              reviewCard
            }
          }.padding(.vertical, 4)
          Button("Choose lessons", systemImage: "list.bullet") { action(.chooseLessons) }
            .accessibilityIdentifier("home.chooseLessons").disabled(lessonsUnavailable)
          if let message = data.studyUnavailableMessage ?? data.lessonsDisabledMessage {
            Text(message).font(.callout).foregroundStyle(.secondary)
          }
        }
        Section("Upcoming reviews") {
          if let message = data.scheduleUnavailableMessage {
            Text(message).foregroundStyle(.secondary).accessibilityIdentifier(
              "home.scheduleUnavailable")
          } else {
            Button {
              action(.forecast)
            } label: {
              VStack(alignment: .leading, spacing: 10) {
                Text(
                  data.hourlyReviews.dropFirst().reduce(0, +) == 0
                    ? "Nothing more in the next 24 hours"
                    : "+\(data.hourlyReviews.dropFirst().reduce(0,+)) in the next 24 hours"
                ).font(.caption).foregroundStyle(.secondary)
                if data.hourlyReviews.contains(where: { $0 > 0 }) {
                  Chart(Array(data.hourlyReviews.enumerated()), id: \.offset) { hour, count in
                    BarMark(x: .value("Hour", hour), y: .value("Reviews", count))
                      .foregroundStyle(hour == 0 ? StudyPalette.kanji : StudyPalette.radical)
                  }.frame(height: 115).chartXScale(
                    domain: -0.5...Double(max(24, data.hourlyReviews.count)) - 0.5
                  )
                  .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24].filter { $0 < data.hourlyReviews.count }) {
                      value in
                      if let hour = value.as(Int.self) {
                        AxisValueLabel {
                          if hour == 0 {
                            Text("Now")
                          } else {
                            Text(
                              data.date.addingTimeInterval(Double(hour) * 3600),
                              format: .dateTime.hour())
                          }
                        }
                      }
                    }
                  }
                  .chartYAxis { AxisMarks(position: .leading) }
                }
              }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary)
            }.buttonStyle(.plain).accessibilityElement(children: .ignore)
              .accessibilityLabel(
                "Upcoming reviews: \(data.hourlyReviews.first ?? 0) now, \(data.hourlyReviews.dropFirst().reduce(0,+)) more in the next 24 hours"
              )
              .accessibilityHint("Shows the full forecast").accessibilityIdentifier("home.forecast")
              .accessibilityAddTraits(.isButton)
          }
          if let next = data.timing.first { LabeledContent(next.id, value: next.value) }
        }
        if data.apprenticePractice + data.recentLessons + data.recentMistakes + data.leeches > 0 {
          Section("Extra study") {
            Text("Additional practice outside your scheduled reviews.")
              .font(.caption).foregroundStyle(.secondary)
            if data.apprenticePractice > 0 {
              countButton(
                "Extra practice", count: data.apprenticePractice, action: .apprenticePractice)
            }
            if data.recentLessons > 0 {
              countButton(
                "Review recent lessons", count: data.recentLessons, action: .recentLessons)
            }
            if data.recentMistakes > 0 {
              countButton(
                "Review recent mistakes", count: data.recentMistakes, action: .recentMistakes)
            }
            if data.leeches > 0 {
              countButton("Review all leeches", count: data.leeches, action: .leeches)
            }
          }
        }
      }
      ForEach(data.levels) { level in
        Section(
          data.levels.count > 1 && level.id != data.levels.last?.id
            ? "Previous level (\(level.id))" : "Current level (\(level.id))"
        ) {
          ForEach(level.progress) { row in
            VStack(alignment: .leading, spacing: 7) {
              LabeledContent(title(row.kind), value: "\(row.guru) of \(row.total) at Guru").font(
                .subheadline)
              Chart {
                BarMark(x: .value("Items", row.guru), y: .value("Subject", "Progress"))
                  .foregroundStyle(StudyPalette.color(for: row.kind))
                BarMark(x: .value("Items", row.apprentice), y: .value("Subject", "Progress"))
                  .foregroundStyle(StudyPalette.color(for: row.kind).opacity(0.45))
                BarMark(x: .value("Items", row.lessons), y: .value("Subject", "Progress"))
                  .foregroundStyle(Color.gray.opacity(0.5))
                BarMark(x: .value("Items", row.locked), y: .value("Subject", "Progress"))
                  .foregroundStyle(Color.gray.opacity(0.2))
              }.chartXScale(domain: 0...max(row.total, 1)).chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 12)
            }.padding(.vertical, 4).accessibilityElement(children: .ignore)
              .accessibilityLabel(
                "\(title(row.kind)): \(row.guru) of \(row.total) at Guru, \(row.apprentice) in Apprentice, \(row.lessons) in lessons, \(row.locked) locked"
              )
              .accessibilityIdentifier("home.level.\(level.id).\(row.kind.rawValue)")
          }
          if level.id == data.levels.last?.id && !data.onVacation && !data.timing.isEmpty {
            ForEach(Array(data.timing.dropFirst())) { item in
              LabeledContent(item.id, value: item.value)
            }
            Text(
              "Timing uses SRS intervals and past pace. It assumes correct, on-time reviews and is a scenario, not a guarantee."
            ).font(.caption).foregroundStyle(.secondary)
          }
          navigationButton(
            "Show remaining", id: "home.remaining.\(level.id)", action: .remaining(level.id))
          navigationButton("Show all", id: "home.catalog.\(level.id)", action: .catalog(level.id))
        }
      }
      Section("All levels") {
        if let message = data.progressUnavailableMessage {
          Text(message).foregroundStyle(.secondary)
        } else {
          Chart(Array(data.stageCounts.enumerated()), id: \.offset) { index, count in
            BarMark(x: .value("Items", count), y: .value("SRS", "Progress")).foregroundStyle(
              stageColors[min(index, 4)])
          }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 16)
            .accessibilityLabel("SRS distribution. Counts are listed below.")
          ForEach(StudySRSCategory.allCases, id: \.self) { category in
            let index = category.rawValue
            let count = data.stageCounts.indices.contains(index) ? data.stageCounts[index] : 0
            Button {
              action(.stage(index))
            } label: {
              HStack {
                Circle().fill(stageColors[index]).frame(width: 10, height: 10)
                Text(category.name).foregroundStyle(.primary)
                Spacer()
                Text(count.formatted()).foregroundStyle(.secondary)
                if count > 0 {
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(count == 0).accessibilityIdentifier(
              "home.stage.\(index)")
            if index == 4 && count > 0 {
              navigationButton("Review burned items", id: "home.burned", action: .burned)
            }
          }
        }
        if data.excluded > 0 {
          countButton("Excluded items", count: data.excluded, action: .excluded)
        }
      }
    }
    .listStyle(.inset)
    .frame(maxWidth: 960).frame(maxWidth: .infinity)
    .tint(StudyPalette.radical)
    .refreshable { await refresh() }.accessibilityIdentifier("home.dashboard")
  }
  private func title(_ kind: SubjectKind) -> String {
    switch kind {
    case .radical: "Radicals"
    case .kanji: "Kanji"
    case .vocabulary: "Vocabulary"
    }
  }
  private func navigationButton(_ title: String, id: String, action: HomeAction) -> some View {
    Button {
      self.action(action)
    } label: {
      HStack {
        Text(title)
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier(id)
      .disabled(action == .burned && data.studyUnavailableMessage != nil)
  }
  private func countButton(_ title: String, count: Int, action: HomeAction) -> some View {
    Button {
      self.action(action)
    } label: {
      LabeledContent(title, value: count.formatted()).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("home.extra.\(String(describing: action))")
      .disabled(action != .excluded && data.studyUnavailableMessage != nil)
  }
  private var lessonsUnavailable: Bool {
    data.lessons == 0 || data.lessonsDisabledMessage != nil || data.studyUnavailableMessage != nil
  }
  private var lessonCard: some View {
    studyButton(
      "Lessons", count: data.lessons, symbol: "book.closed", color: StudyPalette.kanji,
      action: .lessons, disabled: lessonsUnavailable
    )
    .accessibilityLabel("Lessons, \(data.lessonsDisabledMessage ?? "\(data.lessons) available")")
    .accessibilityIdentifier("home.lessons")
  }
  private var reviewCard: some View {
    studyButton(
      "Reviews", count: data.reviews, symbol: "rectangle.stack", color: StudyPalette.radical,
      action: .reviews, disabled: data.reviews == 0 || data.studyUnavailableMessage != nil
    )
    .accessibilityLabel("Start reviews, \(data.reviews) ready").accessibilityIdentifier(
      "home.reviews")
  }
  private func studyButton(
    _ title: String, count: Int, symbol: String, color: Color, action: HomeAction, disabled: Bool
  ) -> some View {
    Button {
      self.action(action)
    } label: {
      HStack {
        Label(title, systemImage: symbol).font(.headline)
        Spacer()
        Text(count.formatted()).font(.title2.bold()).monospacedDigit()
      }.foregroundStyle(isEnabled && !disabled ? Color.white : Color.primary)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }.buttonStyle(.glassProminent).controlSize(.large).tint(color).disabled(disabled)
  }
}
