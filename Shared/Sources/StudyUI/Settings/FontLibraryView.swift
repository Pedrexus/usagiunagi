import Foundation
import SwiftUI

public struct StudyFontOption: Identifiable {
  public let id: String
  public let title: String
  public let previewText: String
  public let fontName: String?
  public let preview: Image?
  public let sizeBytes: Int64
  public let progress: Progress?
  public let error: String?

  public init(
    id: String, title: String, previewText: String, fontName: String?, preview: Image?,
    sizeBytes: Int64, progress: Progress?, error: String?
  ) {
    self.id = id
    self.title = title
    self.previewText = previewText
    self.fontName = fontName
    self.preview = preview
    self.sizeBytes = sizeBytes
    self.progress = progress
    self.error = error
  }
}

public enum FontLibraryAction {
  case download(String)
  case cancel(String)
  case select(String, Bool)
  case deleteAll
}

public struct FontLibraryView: View {
  let options: [StudyFontOption]
  let selected: Set<String>
  let canDelete: Bool
  let deletionError: String?
  let action: (FontLibraryAction) -> Void
  @State private var confirmingDeletion = false

  public init(
    options: [StudyFontOption], selected: Set<String>, canDelete: Bool, deletionError: String?,
    action: @escaping (FontLibraryAction) -> Void
  ) {
    self.options = options
    self.selected = selected
    self.canDelete = canDelete
    self.deletionError = deletionError
    self.action = action
  }

  public var body: some View {
    Form {
      Section {
        Text(
          "Choose the Japanese fonts to use in reviews. A selected font is chosen for each new subject. With none selected, reviews use the default Japanese font."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      ForEach(options) { font in
        Section {
          VStack(alignment: .leading, spacing: 12) {
            if font.fontName != nil {
              Toggle(
                font.title,
                isOn: Binding(
                  get: { selected.contains(font.id) }, set: { action(.select(font.id, $0)) })
              )
              .accessibilityIdentifier("font.selection.\(font.id)")
            } else {
              HStack {
                Text(font.title).font(.headline)
                Spacer()
                if font.progress != nil {
                  Button("Cancel", systemImage: "xmark.circle") { action(.cancel(font.id)) }
                    .accessibilityIdentifier("font.cancel.\(font.id)")
                } else {
                  Button(font.error == nil ? "Download" : "Retry", systemImage: "arrow.down.circle")
                  { action(.download(font.id)) }
                  .accessibilityIdentifier("font.download.\(font.id)")
                }
              }
            }
            if let progress = font.progress {
              ProgressView(progress).accessibilityLabel("Downloading \(font.title)")
                .accessibilityIdentifier("font.progress.\(font.id)")
            }
            Group {
              if let name = font.fontName {
                Text(font.previewText).font(.custom(name, size: 24)).lineLimit(2)
              } else if let preview = font.preview {
                preview.resizable().renderingMode(.template).scaledToFit()
                  .foregroundStyle(.primary).frame(maxHeight: 100)
              }
            }.accessibilityHidden(true)
            if font.fontName == nil {
              Text(font.sizeBytes.formatted(.byteCount(style: .file))).font(.caption)
                .foregroundStyle(.secondary)
            }
            if let error = font.error {
              Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier(
                "font.error.\(font.id)")
            }
          }.padding(.vertical, 4).accessibilityElement(children: .contain)
        }
      }
      if canDelete {
        Section {
          Button("Delete all downloaded fonts", systemImage: "trash", role: .destructive) {
            confirmingDeletion = true
          }
          .accessibilityIdentifier("fonts.deleteAll")
          .confirmationDialog(
            "Delete all downloaded fonts?", isPresented: $confirmingDeletion,
            titleVisibility: .visible
          ) {
            Button("Delete downloaded fonts", role: .destructive) { action(.deleteAll) }
          } message: {
            Text(
              "Downloads will stop and your font selection will be cleared. Reviews will use the default Japanese font."
            )
          }
        }
      }
      if let deletionError { Text(deletionError).foregroundStyle(.red) }
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .navigationTitle("Select Fonts")
  }
}
