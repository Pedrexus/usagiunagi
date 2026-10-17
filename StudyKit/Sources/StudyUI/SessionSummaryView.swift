import StudyCore
import SwiftUI

/// Read-only results; hosts supply cached images and retain subject navigation during migration.
public struct SessionSummaryView: View {
  private let summary: StudySessionSummary
  private let japaneseFont: String
  private let image: (Int) -> Image?
  private let openSubject: (Int) -> Void
  public init(
    summary: StudySessionSummary, japaneseFont: String = "",
    image: @escaping (Int) -> Image? = { _ in nil }, openSubject: @escaping (Int) -> Void
  ) {
    self.summary = summary
    self.japaneseFont = japaneseFont
    self.image = image
    self.openSubject = openSubject
  }
  public var body: some View {
    List {
      Section {
        Label("Session complete", systemImage: "checkmark.circle")
          .font(.title2).accessibilityAddTraits(.isHeader)
        LabeledContent("Accuracy", value: summary.accuracy.map { "\($0)%" } ?? "–")
          .accessibilityIdentifier("summary.accuracy")
        LabeledContent("Correct", value: "\(summary.correctCount)/\(summary.entries.count)")
          .accessibilityIdentifier("summary.correct")
      } footer: {
        Text("Counts completed subjects. A missed meaning or reading makes that subject incorrect.")
      }
      ForEach(summary.missedGroups) { group in
        Section(
          group.id <= 0
            ? "Missed items"
            : group.id == summary.currentLevel
              ? "Missed · current level (\(group.id))" : "Missed · level \(group.id)"
        ) {
          ForEach(group.entries) { entry in
            if let subject = entry.subject {
              Button {
                openSubject(entry.id)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    if let image = image(entry.id) {
                      image.resizable().scaledToFit().frame(width: 32, height: 32)
                        .accessibilityLabel("Radical image")
                    } else if !subject.characters.isEmpty {
                      Text(subject.characters).font(
                        japaneseFont.isEmpty
                          ? .title2 : .custom(japaneseFont, size: 24, relativeTo: .title2))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                  }
                  if !subject.meaning.isEmpty { Text(subject.meaning) }
                  if !subject.readings.isEmpty {
                    Text(subject.readings.joined(separator: ", "))
                      .font(
                        japaneseFont.isEmpty
                          ? .body : .custom(japaneseFont, size: 17, relativeTo: .body))
                  }
                  if entry.meaningWrong {
                    Label("Meaning missed", systemImage: "xmark.circle").foregroundStyle(.secondary)
                  }
                  if entry.readingWrong {
                    Label("Reading missed", systemImage: "xmark.circle").foregroundStyle(.secondary)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("summary.subject.\(entry.id)")
            } else {
              Label("Subject content unavailable", systemImage: "exclamationmark.triangle")
            }
          }
        }
      }
    }
  }
}
