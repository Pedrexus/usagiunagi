import SwiftUI
import WidgetKit

struct StudyComplicationEntry: TimelineEntry {
  let date: Date
  let state: WatchCompanionState

  var snapshot: WatchCompanionSnapshot? {
    guard state.source != .legacyCharacter, let value = state.snapshot,
      date < value.expiresAt
    else { return nil }
    return value
  }
  var isLevel: Bool { state.source == .level }
  var title: String { isLevel ? "Level" : "Reviews" }
  var symbol: String { isLevel ? "chart.bar.fill" : "book.closed" }
  var value: String {
    guard let snapshot else { return "—" }
    if isLevel { return snapshot.levelLabel }
    return snapshot.reviewCounts(at: date).map { String($0.due) } ?? "—"
  }
  var detail: String {
    if state.source == .legacyCharacter { return "Choose Reviews or Level on your watch" }
    guard let snapshot else { return "Open the phone app to update" }
    if isLevel { return "\(snapshot.remaining) remaining" }
    guard let counts = snapshot.reviewCounts(at: date) else { return "Data unavailable" }
    return "\(counts.next) next hour"
  }
  var nextReviewDate: Date? {
    guard !isLevel, let snapshot, let counts = snapshot.reviewCounts(at: date),
      counts.due == 0, counts.next == 0
    else { return nil }
    let next = Date(timeIntervalSince1970: TimeInterval(snapshot.nextReview))
    return next > date && next <= date.addingTimeInterval(86400) ? next : nil
  }
}

struct StudyComplicationProvider: TimelineProvider {
  func placeholder(in _: Context) -> StudyComplicationEntry {
    StudyComplicationEntry(date: .now, state: WatchCompanionState())
  }

  func getSnapshot(in _: Context, completion: @escaping (StudyComplicationEntry) -> Void) {
    completion(StudyComplicationEntry(date: .now, state: WatchCompanionCache.widgetState()))
  }

  func getTimeline(in _: Context, completion: @escaping (Timeline<StudyComplicationEntry>) -> Void)
  {
    let state = WatchCompanionCache.widgetState()
    let now = Date.now
    let dates = [now] + (state.snapshot?.timelineDates(after: now) ?? [])
    completion(
      Timeline(
        entries: dates.map { StudyComplicationEntry(date: $0, state: state) },
        policy: .never))
  }
}

struct StudyComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: StudyComplicationEntry

  var body: some View {
    if #available(watchOS 10.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content
    }
  }

  private var content: some View {
    Group {
      switch family {
      case .accessoryInline:
        Label("\(entry.value) \(entry.title.lowercased())", systemImage: entry.symbol)
      case .accessoryCorner:
        Text(entry.value)
          .font(.title3)
          .minimumScaleFactor(0.5)
          .widgetLabel { detailText }
      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          if entry.isLevel, let snapshot = entry.snapshot {
            Gauge(value: snapshot.fraction) {
              Text(entry.title)
            } currentValueLabel: {
              Text(entry.value).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
          } else {
            VStack(spacing: 0) {
              Text(entry.value).font(.title2).minimumScaleFactor(0.5)
              Text(entry.title).font(.caption2)
            }
          }
        }
        .widgetLabel { detailText }
      case .accessoryRectangular:
        VStack(alignment: .leading, spacing: 2) {
          Label(entry.title, systemImage: entry.symbol).font(.caption)
          HStack(alignment: .firstTextBaseline) {
            Text(entry.value).font(.title2).minimumScaleFactor(0.5)
            detailText.font(.caption2).lineLimit(2)
          }
          if entry.isLevel, let snapshot = entry.snapshot {
            ProgressView(value: snapshot.fraction)
          }
        }
      default:
        EmptyView()
      }
    }
    .widgetAccentable()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(entry.title), \(entry.value), \(detailText)"))
  }

  private var detailText: Text {
    if let date = entry.nextReviewDate {
      Text("\(Text(date, style: .relative)) until next")
    } else {
      Text(entry.detail)
    }
  }
}

@main
struct StudyComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchCompanionCache.widgetKind, provider: StudyComplicationProvider())
    {
      StudyComplicationView(entry: $0)
    }
    .configurationDisplayName("usagiunagi")
    .description("Review counts and level progress from your latest phone update.")
    .supportedFamilies([
      .accessoryInline, .accessoryCircular, .accessoryCorner, .accessoryRectangular,
    ])
  }
}
