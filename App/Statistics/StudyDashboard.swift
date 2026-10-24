import Charts
import StudyCore
import SwiftUI

public struct StudyDashboard: View {
  private static let bundledLibrary = try? CurriculumLibrary.bundled()
  public let snapshot: StudySnapshot
  private let metrics: StudyMetrics
  private let library: CurriculumLibrary?
  private let openSubject: (Int64) -> Void
  @State private var page = Page.progress
  @State private var showSources = false
  @State private var availableWidth: CGFloat = 360
  @Environment(\.dynamicTypeSize) private var typeSize
  public enum Page: String, CaseIterable {
    case progress = "Progress"
    case coverage = "Coverage"
    case focus = "Focus"
  }

  public init(
    snapshot: StudySnapshot, now: Date = .now, initialPage: Page = .progress,
    openSubject: @escaping (Int64) -> Void
  ) {
    self._page = State(initialValue: initialPage)
    self.snapshot = snapshot
    self.metrics = snapshot.metrics(now: now)
    self.library = Self.bundledLibrary
    self.openSubject = openSubject
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if snapshot.isSample || snapshot.onVacation || snapshot.pendingReviews > 0 {
          VStack(alignment: .leading, spacing: 6) {
            if snapshot.isSample {
              Label("Sample statistics", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            }
            if snapshot.onVacation {
              Label("Vacation mode", systemImage: "pause.circle").foregroundStyle(.secondary)
            }
            if snapshot.pendingReviews > 0 {
              Label(
                "\(snapshot.pendingReviews) uploads pending. Statistics show synced results.",
                systemImage: "arrow.triangle.2.circlepath"
              )
              .font(.callout).foregroundStyle(.secondary)
            }
          }
        }
        Picker("Statistics section", selection: $page) {
          ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
        if snapshot.requiresAssignmentRefresh {
          ContentUnavailableView(
            "Refresh WaniKani", systemImage: "arrow.clockwise",
            description: Text(
              "Archived answers need fresh progress before statistics can be shown. Refresh this account to reload its assignments."
            ))
        } else {
          switch page {
          case .progress: progress
          case .coverage:
            if let library {
              CurriculumCoverageView(
                snapshot: snapshot, library: library, focus: metrics.focus, openSubject: openSubject
              )
            } else {
              ContentUnavailableView(
                "Curriculum data unavailable", systemImage: "exclamationmark.book.closed",
                description: Text("The bundled source data could not be loaded."))
            }
          case .focus: focus
          }
        }
        DisclosureGroup(isExpanded: $showSources) {
          StudySourcesView(sourceDate: library?.kanjidicDate ?? "Unavailable")
        } label: {
          Label("Sources and calculation details", systemImage: "info.circle")
            .font(.callout)
        }
        .accessibilityIdentifier("statistics.sources")
        Text("Snapshot: \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
      }
      .padding().frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      availableWidth = $0
    }
    .background(.background)
    .tint(StudyPalette.radical)
    .accessibilityIdentifier("StudyDashboard")
  }

  private var progress: some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(
            minimum: min(max(240, availableWidth - 32), typeSize.isAccessibilitySize ? 600 : 340)),
          spacing: 20, alignment: .top)
      ], alignment: .leading, spacing: 20
    ) {
      StudyCard(title: "SRS progress", subtitle: "Your active study stages") {
        Chart(StudySRSCategory.allCases, id: \.self) { category in
          let count = snapshot.assignments.filter {
            StudySRSStage(rawValue: $0.srsStageNumber)?.category == category
          }.count
          BarMark(x: .value("Items", count), y: .value("Stage", category.name))
            .foregroundStyle(StudyPalette.color(for: category))
            .annotation(position: .trailing) {
              Text(count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(height: 190).chartXAxisLabel("Items")
        Text("A stage describes WaniKani review progress, not a test score.").studyNote()
        if !snapshot.pendingSubjectIDs.isEmpty {
          Text(
            "\(snapshot.pendingSubjectIDs.count) items awaiting sync are excluded from these stages."
          )
          .studyNote()
        }

      }
      StudyCard(title: "Answer accuracy", subtitle: "Lifetime answers, separated by question type")
      {
        let rates = [("Meaning", metrics.meaning), ("Reading", metrics.reading)]
        if rates.allSatisfy({ $0.1.fraction == nil }) {
          Text("Review items to build your answer history.").foregroundStyle(.secondary)
        } else {
          Chart(rates, id: \.0) { name, rate in
            if let fraction = rate.fraction {
              BarMark(x: .value("Accuracy", fraction), y: .value("Question", name))
                .foregroundStyle(name == "Meaning" ? StudyPalette.kanji : StudyPalette.vocabulary)
            }
          }.frame(height: 120).chartXScale(domain: 0...1)
            .chartXAxis {
              AxisMarks(values: [0.0, 0.5, 1.0]) {
                AxisGridLine()
                AxisValueLabel(format: Decimal.FormatStyle.Percent.percent)
              }
            }
          ForEach(rates, id: \.0) { name, rate in
            LabeledContent(
              name,
              value: rate.fraction.map {
                $0.formatted(.percent.precision(.fractionLength(1)))
                  + " · \(rate.correct)/\(rate.attempts)"
              } ?? "No answers"
            )
            .font(.callout)
          }
        }
        Text("Answer-weighted accuracy from synced history. It does not measure retention.")
          .studyNote()
      }
      StudyCard(title: "Upcoming reviews", subtitle: "Each item's next scheduled review") {
        if snapshot.onVacation || snapshot.pendingReviews > 0 {
          Label(
            "Schedule available after vacation or pending uploads are resolved.",
            systemImage: "pause.circle"
          ).foregroundStyle(.secondary)
        } else {
          Text("\(metrics.dueNow) due now").font(.title2.bold()).foregroundStyle(
            StudyPalette.radical)
          if metrics.scheduledDays.contains(where: { $0.count > 0 }) {
            Chart(metrics.scheduledDays, id: \.date) { day in
              BarMark(x: .value("Day", day.date, unit: .day), y: .value("Items", day.count))
                .foregroundStyle(StudyPalette.radical)
            }.frame(height: 180)
              .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                  AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
              }
          } else {
            Text("No additional reviews scheduled in the next 7 days.")
              .foregroundStyle(.secondary)
          }
          Text(
            "Local calendar days. Repeat reviews, new lessons and mistakes add work beyond these counts."
          ).studyNote()
        }
      }
      StudyCard(title: "Level pace", subtitle: "Days from unlocking to passing each recent level") {
        if let pace = metrics.pace {
          Chart {
            ForEach(pace.history, id: \.level) { level in
              BarMark(x: .value("Level", String(level.level)), y: .value("Days", level.days))
                .foregroundStyle(StudyPalette.kanji)
            }
            RuleMark(y: .value("Median", pace.medianDays)).foregroundStyle(.secondary).lineStyle(
              StrokeStyle(dash: [4]))
          }.frame(height: 180).chartYAxisLabel("Days")
          Text(
            "Median \(pace.medianDays.formatted(.number.precision(.fractionLength(1)))) days per level"
          ).font(.headline)
          if snapshot.pendingReviews == 0, let range = pace.nextLevelRange {
            Text(
              "At a similar pace: level \(snapshot.currentLevel + 1) around \(range.lowerBound.formatted(date: .abbreviated, time: .omitted))–\(range.upperBound.formatted(date: .abbreviated, time: .omitted))."
            ).font(.callout)
          }
          Text(
            "Up to 8 levels, excluding the first two and recorded resets. Includes breaks. Dates are scenarios, not guarantees."
          ).studyNote()
          if let validation = pace.validation {
            Text(
              "Past average error: \(validation.meanAbsoluteErrorDays.formatted(.number.precision(.fractionLength(1)))) days across \(validation.trials.count) levels."
            )
            .font(.callout).accessibilityIdentifier("statistics.pace.validationSummary")
            DisclosureGroup("Compare past estimates") {
              Chart(validation.trials) { trial in
                RuleMark(
                  x: .value("Level", trial.level),
                  yStart: .value("Lower typical pace", trial.lowerDays),
                  yEnd: .value("Upper typical pace", trial.upperDays)
                )
                .foregroundStyle(StudyPalette.radical.opacity(0.35)).lineStyle(
                  StrokeStyle(lineWidth: 6))
                LineMark(x: .value("Level", trial.level), y: .value("Days", trial.estimatedDays))
                  .foregroundStyle(by: .value("Series", "Estimated"))
                PointMark(x: .value("Level", trial.level), y: .value("Days", trial.actualDays))
                  .foregroundStyle(by: .value("Series", "Actual"))
              }.chartForegroundStyleScale([
                "Estimated": StudyPalette.radical, "Actual": StudyPalette.kanji,
              ])
              .chartXScale(
                domain: .automatic(includesZero: false), range: .plotDimension(padding: 12)
              )
              .chartXAxis { AxisMarks(values: validation.trials.map(\.level)) }
              .chartYAxisLabel("Days").frame(height: 180)
              .accessibilityIdentifier("statistics.pace.validationChart")
              Text(
                "\(validation.withinBandCount) of \(validation.trials.count) levels finished within the typical band. Each estimate uses only levels passed by the time that level started. This checks past pace, not exam readiness or a guaranteed finish date."
              )
              .studyNote().accessibilityIdentifier("statistics.pace.validationNote")
            }
          } else {
            Text(
              "More history is needed to check past estimates: at least 3 earlier levels for each of 3 completed levels."
            ).studyNote()
          }
        } else {
          Text("Complete at least 3 levels after level 2 to see your pace.").foregroundStyle(
            .secondary)
        }
      }
    }
  }

  private var focus: some View {
    StudyCard(title: "Focus next", subtitle: "Repeated errors with limited recovery") {
      let subjects = Dictionary(
        snapshot.subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let items = metrics.focus.compactMap { item in subjects[item.subjectID].map { (item, $0) } }
        .prefix(12)
      if items.isEmpty {
        Label(
          "No recurring trouble items with enough evidence yet.", systemImage: "checkmark.circle"
        ).foregroundStyle(.secondary)
      }
      ForEach(Array(items), id: \.0.subjectID) { item, subject in
        Button {
          openSubject(subject.id)
        } label: {
          HStack(alignment: .top) {
            Text(subject.characters.isEmpty ? subject.meaning : subject.characters)
              .font(.title2).foregroundStyle(StudyPalette.color(for: subject.kind))
              .frame(minWidth: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
              Text(subject.meaning).foregroundStyle(.primary)
              Text(
                "\(item.reading ? "Reading" : "Meaning") · \(item.incorrect) errors in \(item.attempts) answers"
              ).font(.callout).foregroundStyle(.secondary)
              Text("Current correct streak: \(item.streak)").font(.caption).foregroundStyle(
                .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
          }.contentShape(Rectangle()).padding(.vertical, 6)
        }.buttonStyle(.plain)
        Divider()
      }
      Text(
        "Requires 5 answers and 2 errors on a side. Priority falls as the correct streak grows. Tap an item to revisit it."
      ).studyNote()
    }
  }
}

struct StudyCard<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
      }
      content
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
  }
}

extension Text {
  func studyNote() -> some View {
    font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}
