import Charts
import StudyCore
import SwiftUI

struct CurriculumCoverageView: View {
  let snapshot: StudySnapshot
  let library: CurriculumLibrary
  let openSubject: (Int64) -> Void
  @State private var system = CurriculumSystem.jlpt
  @State private var threshold = 5
  @State private var expanded: String?
  private let thresholds = [(1, "Started"), (5, "Guru+"), (7, "Master+"), (9, "Burned")]
  private var thresholdName: String { thresholds.first { $0.0 == threshold }!.1 }
  private var coverage: [CurriculumCoverage] {
    library.curricula(for: system).map {
      CurriculumCoverage(
        curriculum: $0, subjects: snapshot.subjects, assignments: snapshot.assignments,
        threshold: threshold)
    }
  }
  private struct Segment: Identifiable {
    let state: String
    let count: Int
    var id: String { state }
  }
  private func segments(_ row: CurriculumCoverage) -> [Segment] {
    [
      .init(state: thresholdName, count: row.reached),
      .init(state: "Learning", count: row.learning),
      .init(state: "Not started", count: row.notStarted),
      .init(state: "Outside catalog", count: row.outsideCatalog),
    ]
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Picker("System", selection: $system) {
          ForEach(CurriculumSystem.allCases) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("coverage.system")
        Spacer()
        Picker("Count as covered", selection: $threshold) {
          ForEach(thresholds, id: \.0) { value, name in Text(name).tag(value) }
        }
        .accessibilityIdentifier("coverage.threshold")
      }.pickerStyle(.menu)
      StudyCard("Kanji coverage", subtitle: system.explanation) {
        Chart(coverage) { row in
          ForEach(segments(row)) { segment in
            BarMark(
              x: .value("Share", Double(segment.count) / Double(max(1, row.total))),
              y: .value("Target", row.curriculum.title)
            )
            .foregroundStyle(by: .value("Study state", segment.state))
            .accessibilityLabel("\(row.curriculum.title), \(segment.state)")
            .accessibilityValue("\(segment.count) of \(row.total) kanji")
          }
        }
        .frame(height: CGFloat(coverage.count * 42 + 60))
        .chartXScale(domain: 0...1)
        .chartXAxis {
          AxisMarks(values: [0.0, 0.5, 1.0]) {
            AxisGridLine()
            AxisValueLabel(format: Decimal.FormatStyle.Percent.percent)
          }
        }
        .chartForegroundStyleScale(
          domain: [thresholdName, "Learning", "Not started", "Outside catalog"],
          range: [
            StudyPalette.kanji, StudyPalette.vocabulary.opacity(0.65), Color.gray.opacity(0.35),
            Color.gray.opacity(0.12),
          ]
        )
        .accessibilityIdentifier("coverage.chart")
        ForEach(coverage) { row in
          Button {
            expanded = expanded == row.id ? nil : row.id
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(row.curriculum.title).font(.headline).foregroundStyle(.primary)
                Text(
                  "\(row.reached) / \(row.total) at \(thresholdName) · \(row.outsideCatalog) outside synced catalog"
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(row.fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
              Image(systemName: expanded == row.id ? "chevron.up" : "chevron.down").font(.caption)
            }.padding(.vertical, 6).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityValue(expanded == row.id ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide remaining kanji")
            .accessibilityIdentifier("coverage.target.\(row.id)")
          if expanded == row.id {
            CoverageDetail(
              row: row, thresholdName: thresholdName, subjects: snapshot.subjects,
              openSubject: openSubject)
          }
          Divider()
        }
        Text(
          "The denominator includes the entire reference set, including kanji outside WaniKani. Unstarted or unavailable items are never counted as known."
        ).studyNote()
        Text(
          "Reference lists are included with the app. Coverage uses your saved WaniKani data and is available offline."
        ).studyNote()
        if snapshot.pendingReviews > 0 {
          Text("Coverage excludes pending local progress until it syncs.").studyNote()
        }
      }
    }
    .onChange(of: system) { _, _ in expanded = nil }
  }
}

private struct CoverageDetail: View {
  let row: CurriculumCoverage
  let thresholdName: String
  let subjects: [StudySubject]
  let openSubject: (Int64) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(row.remaining.count) remaining kanji").font(.headline)
        .accessibilityIdentifier("coverage.remaining.\(row.id)")
      Text("Below \(thresholdName). This is study coverage, not a passing-score prediction.")
        .studyNote()
      let known = Dictionary(
        subjects.filter { $0.kind == .kanji }.map { ($0.characters, $0) },
        uniquingKeysWith: { first, _ in first })
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
        ForEach(row.remaining, id: \.self) { character in
          if let subject = known[character] {
            Button {
              openSubject(subject.id)
            } label: {
              Text(character).font(.title2).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).tint(StudyPalette.kanji)
            .accessibilityLabel("\(character), \(subject.meaning), WaniKani level \(subject.level)")
            .accessibilityHint("Open subject details")
            .accessibilityIdentifier("coverage.subject.\(subject.id)")
          } else {
            Text(character).font(.title2).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, minHeight: 44)
              .accessibilityLabel("\(character), outside synced catalog")
          }
        }
      }
      Text("Colored kanji open saved subject details. Gray kanji are outside your synced catalog.")
        .studyNote()
    }.padding(.vertical, 8)
  }
}

public struct StudySourcesView: View {
  let sourceDate: String
  public init(sourceDate: String) { self.sourceDate = sourceDate }
  public var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox("What coverage means") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "Coverage matches synced WaniKani kanji to reference sets. Guru+, Master+ and Burned are SRS milestones, not proof of mastery. JLPT counts include easier levels."
          )
          .accessibilityIdentifier("sources.coverage")
          Text(
            "JLPT does not publish current official kanji lists. These estimates cannot assess listening, grammar, vocabulary breadth or reading comprehension. Kanji Kentei also tests handwriting and other skills."
          )
          Link(
            "Official Kanji Kentei character allocations",
            destination: URL(
              string:
                "https://www.kanken.or.jp/kanken/outline/data/outline_degree_national_list20200217.pdf"
            )!)
          Link("JLPT official FAQ", destination: URL(string: "https://www.jlpt.jp/e/faq/")!)
          Link(
            "Kanji Kentei scopes and readiness checks",
            destination: URL(string: "https://www.kanken.or.jp/kanken/grades/meyasucheck/")!)
        }
      }
      GroupBox("Curriculum sources") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "School grades and Jōyō: KANJIDIC2, © James William BREEN and the Electronic Dictionary Research and Development Group. Snapshot \(sourceDate). Fields reduced to character classifications; canonical equivalents deduplicated."
          )
          Link(
            "KANJIDIC project",
            destination: URL(string: "https://www.edrdg.org/wiki/index.php/KANJIDIC_Project")!)
          Link(
            "EDRDG license and attribution",
            destination: URL(string: "https://www.edrdg.org/edrdg/licence.html")!)
          Link(
            "Derived data: CC BY-SA 4.0",
            destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
          Text(
            "Estimated JLPT lists: Jonathan Waller / Tanos, via David Gouveia's kanji-data, revision 00fd707. The full source notice and MIT license are included with the app resources."
          )
          Link(
            "kanji-data source",
            destination: URL(string: "https://github.com/davidluzgouveia/kanji-data")!)
          Link(
            "Jonathan Waller's JLPT resources",
            destination: URL(string: "https://www.tanos.co.uk/jlpt/")!)
        }
      }
      GroupBox("Calculations") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "Accuracy: total correct answers / total answers, separately for reading and meaning, excluding hidden items. Schedule: one next review per active item, not total future work."
          )
          Text(
            "Pace: median of up to eight passed levels after level 2 and recorded resets. Dates use historical quartiles; they are not calibrated confidence intervals."
          )
          Text(
            "Focus priority: (errors + 1) / (answers + 2) / √(correct streak + 1), with at least five answers and two errors. Recovery lowers priority."
          )
        }
      }
    }
    .font(.callout)
    .fixedSize(horizontal: false, vertical: true)
  }
}
