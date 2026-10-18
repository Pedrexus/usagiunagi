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

public struct HomeDashboardData: Sendable {
  public struct Level: Identifiable, Sendable {
    public let id: Int
    public let progress: [StudyLevelProgress]
    public init(number: Int, progress: [StudyLevelProgress]) {
      id = number
      self.progress = progress
    }
  }
  public struct Metric: Identifiable, Sendable {
    public let id: String
    public let value: String
    public init(_ title: String, _ value: String) {
      id = title
      self.value = value
    }
  }
  public var onVacation = false
  public var reviews = 0, lessons = 0, apprenticePractice = 0
  public var recentLessons = 0, recentMistakes = 0, leeches = 0, excluded = 0
  public var lessonsDisabledMessage: String?
  public var hourlyReviews: [Int] = []
  public var levels: [Level] = []
  public var timing: [Metric] = []
  public var stageCounts: [Int] = []
  public var date = Date.now
  public init() {}
}

public struct HomeDashboardView: View {
  let data: HomeDashboardData
  let action: (HomeAction) -> Void
  let refresh: () async -> Void
  private let stageNames = ["Apprentice", "Guru", "Master", "Enlightened", "Burned"]
  private let stageColors: [Color] = [
    StudyPalette.kanji, StudyPalette.vocabulary,
    Color(red: 47.0 / 255, green: 85.0 / 255, blue: 181.0 / 255),
    Color(red: 47.0 / 255, green: 127.0 / 255, blue: 181.0 / 255), .primary,
  ]
  public init(
    data: HomeDashboardData, action: @escaping (HomeAction) -> Void,
    refresh: @escaping () async -> Void
  ) {
    self.data = data
    self.action = action
    self.refresh = refresh
  }
  public var body: some View {
    List {
      if !data.onVacation {
        Section {
          VStack(spacing: 12) {
            studyButton(
              "Start reviews", subtitle: "\(data.reviews) ready", symbol: "rectangle.stack",
              enabled: data.reviews > 0, prominent: true, action: .reviews)
            studyButton(
              "Lessons", subtitle: data.lessonsDisabledMessage ?? "\(data.lessons) available",
              symbol: "book", enabled: data.lessons > 0 && data.lessonsDisabledMessage == nil,
              action: .lessons)
            studyButton(
              "Extra practice", subtitle: "\(data.apprenticePractice) items back in Apprentice",
              symbol: "arrow.trianglehead.2.clockwise.rotate.90",
              enabled: data.apprenticePractice > 0, action: .apprenticePractice)
            studyButton(
              "Choose lessons", symbol: "list.bullet",
              enabled: data.lessons > 0 && data.lessonsDisabledMessage == nil,
              action: .chooseLessons)
          }.padding(.vertical, 4)
        }
        Section("Upcoming reviews") {
          Button {
            action(.forecast)
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              Text(
                data.hourlyReviews.dropFirst().reduce(0, +) == 0
                  ? "Nothing more in the next 24 hours"
                  : "+\(data.hourlyReviews.dropFirst().reduce(0,+)) in the next 24 hours"
              ).font(.caption).foregroundStyle(.secondary)
              Chart(Array(data.hourlyReviews.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", hour), y: .value("Reviews", count))
                  .foregroundStyle(hour == 0 ? StudyPalette.kanji : StudyPalette.radical)
              }.frame(height: 115).chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                  AxisMarks(values: [0, 6, 12, 18]) { value in
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
            }.foregroundStyle(.primary)
          }.buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "Upcoming reviews: \(data.hourlyReviews.first ?? 0) now, \(data.hourlyReviews.dropFirst().reduce(0,+)) more in the next 24 hours"
            )
            .accessibilityHint("Shows the full forecast").accessibilityIdentifier("home.forecast")
            .accessibilityAddTraits(.isButton)
          if let next = data.timing.first { LabeledContent(next.id, value: next.value) }
          if data.recentLessons > 0 {
            countButton("Review recent lessons", count: data.recentLessons, action: .recentLessons)
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
          if level.id == data.levels.last?.id && !data.onVacation {
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
        Chart(Array(data.stageCounts.enumerated()), id: \.offset) { index, count in
          BarMark(x: .value("Items", count), y: .value("SRS", "Progress")).foregroundStyle(
            stageColors[min(index, 4)])
        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 16)
          .accessibilityLabel("SRS distribution. Counts are listed below.")
        ForEach(Array(data.stageCounts.prefix(5).enumerated()), id: \.offset) { index, count in
          Button {
            action(.stage(index))
          } label: {
            HStack {
              Circle().fill(stageColors[index]).frame(width: 10, height: 10)
              Text(stageNames[index]).foregroundStyle(.primary)
              Spacer()
              Text(count.formatted()).foregroundStyle(.secondary)
              if count > 0 {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
              }
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).disabled(count == 0).accessibilityIdentifier("home.stage.\(index)")
          if index == 4 && count > 0 {
            navigationButton("Review burned items", id: "home.burned", action: .burned)
          }
        }
        if data.excluded > 0 {
          countButton("Excluded items", count: data.excluded, action: .excluded)
        }
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #endif
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
  }
  private func countButton(_ title: String, count: Int, action: HomeAction) -> some View {
    Button {
      self.action(action)
    } label: {
      LabeledContent(title, value: count.formatted()).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
  @ViewBuilder private func studyButton(
    _ title: String, subtitle: String? = nil, symbol: String, enabled: Bool,
    prominent: Bool = false, action: HomeAction
  ) -> some View {
    let button = Button {
      self.action(action)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.body.weight(.semibold))
          if let subtitle { Text(subtitle).font(.caption) }
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }.disabled(!enabled).accessibilityLabel(
      [title, subtitle].compactMap { $0 }.joined(separator: ", "))
    if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
  }
}
