import StudyCore
import SwiftUI

/// Read-only results; hosts supply cached images and retain subject navigation during migration.
struct SessionSummaryView: View {
  let summary: StudySessionSummary
  var title = "Session complete"
  var message: String? = nil
  var japaneseFont = ""
  var imageURL: (Int) -> URL? = { _ in nil }
  var image: (Int) -> Image? = { _ in nil }
  let openSubject: (Int) -> Void
  var body: some View {
    List {
      Section {
        Label(title, systemImage: "checkmark.circle")
          .font(.title2).accessibilityAddTraits(.isHeader)
        LabeledContent("Accuracy", value: summary.accuracy.map { "\($0)%" } ?? "–")
          .accessibilityIdentifier("summary.accuracy")
        LabeledContent("Correct", value: "\(summary.correctCount)/\(summary.entries.count)")
          .accessibilityIdentifier("summary.correct")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "Counts completed subjects. A missed meaning or reading makes that subject incorrect.")
          if let message { Text(message) }
        }
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
                    } else if let url = imageURL(entry.id) {
                      RadicalImageView(url: url).frame(width: 32, height: 32)
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
