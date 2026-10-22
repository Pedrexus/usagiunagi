import Charts
import StudyCore
import SwiftUI

public enum HomeAction: Hashable, Sendable {
  case reviews, lessons, chooseLessons, apprenticePractice, recentLessons, recentMistakes, leeches,
    burned, forecast, excluded
  case catalog(Int)
  case remaining(Int)
  case stage(Int)
  case subject(Int64)
  case levelSubjects(Int, SubjectKind)
}

struct HomeDashboardView: View {
  let data: HomeDashboardData
  let state: StudyShellState
  let action: (HomeAction) -> Void
  let refresh: () async -> Void
  var resume: (() -> Void)? = nil
  @Environment(\.isEnabled) private var isEnabled
  @FocusState private var keyboardFocus: Bool
  var body: some View {
    Form {
      Section {
        HStack(spacing: 12) {
          StudyAvatarView(url: state.avatar, revision: state.avatarRevision).frame(
            width: 42, height: 42)
          VStack(alignment: .leading, spacing: 3) {
            Text(state.username).font(.headline).accessibilityIdentifier("app.username")
            Text(
              state.level == 0
                ? "Connect your WaniKani account"
                : state.learnedKanji.map {
                  "Level \(state.level) · \($0.formatted()) kanji learned"
                }
                  ?? "Level \(state.level)"
            ).font(.subheadline).accessibilityIdentifier("app.level")
          }.frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if data.onVacation {
        Section {
          Label("Vacation mode", systemImage: "pause.circle").font(.headline)
            .accessibilityIdentifier("app.vacation")
          Text(
            "Your account is on vacation, so lessons and reviews are paused. Turn off vacation mode on the WaniKani website."
          ).font(.callout)
          Link("Open WaniKani", destination: URL(string: "https://www.wanikani.com")!)
            .accessibilityIdentifier("app.vacation.website")
        }
      }
      if let notice = data.notice {
        Text(notice).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier(
          "home.notice")
      }
      if let title = data.resumeTitle, let resume {
        Button(title, systemImage: "play.circle", action: resume)
          .font(.headline).accessibilityIdentifier("home.resume")
      }
      if !data.onVacation {
        Section {
          lessonCard
          reviewCard
          navigationButton(
            "Choose lessons", id: "home.chooseLessons", action: .chooseLessons
          ).disabled(lessonsUnavailable)
        } header: {
          Text("Available now").foregroundStyle(Color.primary)
            .accessibilityIdentifier("home.availableHeading")
        } footer: {
          if let message = data.studyUnavailableMessage ?? data.lessonsDisabledMessage {
            Text(message).font(.callout).foregroundStyle(.secondary)
          }
        }
        forecast
        Section {
          if data.recentMistakes > 0 {
            countButton(
              "Review recent mistakes", count: data.recentMistakes, action: .recentMistakes)
          } else if data.studyUnavailableMessage == nil {
            Label("No recent mistakes to review", systemImage: "checkmark.seal")
              .foregroundStyle(Color.primary)
          }
        } header: {
          Label("Recent mistakes", systemImage: "arrow.counterclockwise").foregroundStyle(
            Color.primary)
        } footer: {
          Text("Revisit items you answered incorrectly in the last 24 hours.").foregroundStyle(
            Color.primary)
        }
        if data.apprenticePractice + data.recentLessons + data.leeches > 0 {
          Section {
            Text("Additional practice outside your scheduled reviews.")
              .font(.caption).foregroundStyle(Color.primary)
            if data.apprenticePractice > 0 {
              countButton(
                "Extra practice", count: data.apprenticePractice, action: .apprenticePractice)
            }
            if data.recentLessons > 0 {
              countButton(
                "Review recent lessons", count: data.recentLessons, action: .recentLessons)
            }
            if data.leeches > 0 {
              countButton("Review all leeches", count: data.leeches, action: .leeches)
            }
          } header: {
            Text("Extra study").foregroundStyle(Color.primary)
          }
        }
      }
      ForEach(data.levels) { level in
        Section {
          ForEach(level.progress) { row in
            Button {
              action(.levelSubjects(level.id, row.kind))
            } label: {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Label {
                    Text(title(row.kind)).foregroundStyle(Color.primary)
                  } icon: {
                    Image(systemName: row.kind == .radical ? "square.grid.2x2" : "character")
                      .foregroundStyle(StudyPalette.color(for: row.kind))
                  }
                  Spacer()
                  Text("\(row.guru) / \(row.total)").monospacedDigit()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
                ProgressView(value: Double(row.guru), total: Double(max(1, row.total)))
                  .tint(StudyPalette.color(for: row.kind))
              }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityElement(children: .ignore)
              .accessibilityLabel(
                "\(title(row.kind)): \(row.guru) of \(row.total) at Guru, \(row.apprentice) in Apprentice, \(row.lessons) in lessons, \(row.locked) locked"
              )
              .accessibilityIdentifier("home.level.\(level.id).\(row.kind.rawValue)")
          }
          if level.id == data.levels.last?.id && !data.onVacation && !data.timing.isEmpty {
            DisclosureGroup("Level-up estimates") {
              ForEach(Array(data.timing.dropFirst())) { item in
                LabeledContent(item.id, value: item.value)
              }
              Text(
                "Timing uses SRS intervals and past pace. It assumes correct, on-time reviews and is a scenario, not a guarantee."
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          navigationButton(
            "Show remaining", id: "home.remaining.\(level.id)", action: .remaining(level.id))
          navigationButton("Show all", id: "home.catalog.\(level.id)", action: .catalog(level.id))
        } header: {
          Text(
            data.levels.count > 1 && level.id != data.levels.last?.id
              ? "Previous level (\(level.id))" : "Current level (\(level.id))"
          ).foregroundStyle(Color.primary)
        }
      }
      Section("Item spread · All levels") {
        if let message = data.progressUnavailableMessage {
          Text(message).foregroundStyle(.secondary)
        } else {
          Chart(Array(data.stageCounts.enumerated()), id: \.offset) { index, count in
            BarMark(x: .value("Items", count), y: .value("SRS", "Progress")).foregroundStyle(
              StudyPalette.color(for: StudySRSCategory(rawValue: index) ?? .burned))
          }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 16)
            .accessibilityLabel("SRS distribution. Counts are listed below.")
          ForEach(StudySRSCategory.allCases, id: \.self) { category in
            let index = category.rawValue
            let count = data.stageCounts.indices.contains(index) ? data.stageCounts[index] : 0
            Button {
              action(.stage(index))
            } label: {
              HStack {
                Image(systemName: category == .burned ? "flame.fill" : "leaf.fill")
                  .foregroundStyle(StudyPalette.color(for: category)).frame(width: 24)
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
      if data.progressUnavailableMessage == nil && data.studyUnavailableMessage == nil {
        recentSubjects("Recently unlocked", symbol: "lock.open", subjects: data.recentlyUnlocked)
        recentSubjects("Recently burned", symbol: "flame", subjects: data.recentlyBurned)
      }
      Section {
        Link(destination: URL(string: "https://community.wanikani.com")!) {
          Label("WaniKani community", systemImage: "bubble.left.and.bubble.right")
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: 960).frame(maxWidth: .infinity)
    .tint(StudyPalette.radical)
    .refreshable { await refresh() }.accessibilityIdentifier("home.dashboard")
    .focusable().focused($keyboardFocus)
    .onAppear { keyboardFocus = true }
    .onKeyPress(keys: [.return], action: openStudy)
  }
  private func recentSubjects(_ title: String, symbol: String, subjects: [StudySubject])
    -> some View
  {
    Section {
      if subjects.isEmpty {
        Text("No items in the last 30 days.").foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 8) {
            ForEach(subjects) { subject in
              Button {
                action(.subject(subject.id))
              } label: {
                Text(subject.characters.isEmpty ? subject.meaning : subject.characters)
                  .font(.title3).padding(12).frame(minHeight: 44)
                  .foregroundStyle(.white)
                  .background(StudyPalette.color(for: subject.kind), in: .rect(cornerRadius: 10))
              }.buttonStyle(.plain)
                .accessibilityLabel("\(subject.characters), \(subject.meaning)")
                .accessibilityIdentifier("home.recent.\(subject.id)")
            }
          }
        }.scrollIndicators(.hidden)
      }
    } header: {
      Label("\(title) · \(subjects.count)", systemImage: symbol)
    } footer: {
      Text("Confirmed WaniKani activity in the last 30 days.")
    }
  }
  private var forecast: some View {
    Section {
      if let message = data.scheduleUnavailableMessage {
        Text(message).foregroundStyle(.secondary).accessibilityIdentifier(
          "home.scheduleUnavailable")
      } else {
        Button {
          action(.forecast)
        } label: {
          VStack(alignment: .leading, spacing: 10) {
            let upcoming = data.hourlyReviews.dropFirst().reduce(0, +)
            LabeledContent("Next 24 hours", value: "+\(upcoming) items")
              .font(.headline).foregroundStyle(.primary)
            if data.hourlyReviews.contains(where: { $0 > 0 }) {
              Chart(Array(data.hourlyReviews.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", hour), y: .value("Reviews", count))
                  .foregroundStyle(hour == 0 ? StudyPalette.kanji : StudyPalette.radical)
              }.frame(height: 115).chartXScale(
                domain: -0.5...(Double(max(24, data.hourlyReviews.count)) - 0.5)
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
    } header: {
      Text("Upcoming reviews").foregroundStyle(Color.primary)
        .accessibilityIdentifier("home.forecastHeading")
    }
  }
  private func openStudy(_ press: KeyPress) -> KeyPress.Result {
    guard isEnabled, !data.onVacation, press.modifiers.isEmpty else { return .ignored }
    if !reviewsUnavailable {
      action(.reviews)
    } else if !lessonsUnavailable {
      action(.lessons)
    } else {
      return .ignored
    }
    return .handled
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
  private var reviewsUnavailable: Bool {
    data.reviews == 0 || data.studyUnavailableMessage != nil
  }
  private var lessonCard: some View {
    studyButton(
      "Lessons", count: data.lessons, symbol: "book.closed", color: StudyPalette.kanji,
      action: .lessons, disabled: lessonsUnavailable
    )
    .accessibilityLabel("Lessons, \(data.lessonsDisabledMessage ?? "\(data.lessons) available")")
    .accessibilityIdentifier("home.lessons")
    .keyboardShortcut("l", modifiers: .command)
  }
  private var reviewCard: some View {
    studyButton(
      "Reviews", count: data.reviews, symbol: "rectangle.stack", color: StudyPalette.radical,
      action: .reviews, disabled: reviewsUnavailable
    )
    .accessibilityLabel("Start reviews, \(data.reviews) ready").accessibilityIdentifier(
      "home.reviews"
    )
    .keyboardShortcut("r", modifiers: .command)
  }
  private func studyButton(
    _ title: String, count: Int, symbol: String, color: Color, action: HomeAction, disabled: Bool
  ) -> some View {
    Button {
      self.action(action)
    } label: {
      HStack {
        Image(systemName: symbol).font(.largeTitle).symbolRenderingMode(.hierarchical)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Text(count.formatted()).font(.title2.bold()).monospacedDigit()
          }
          Text(action == .lessons ? "Learn something new." : "Review to unlock new lessons.")
            .font(.subheadline)
          Label(action == .lessons ? "Start lessons" : "Start reviews", systemImage: "arrow.right")
            .font(.headline)
        }
      }.padding(18).foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(isEnabled && !disabled ? color : Color.gray, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
    }.buttonStyle(.plain).disabled(disabled).listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
  }
}
