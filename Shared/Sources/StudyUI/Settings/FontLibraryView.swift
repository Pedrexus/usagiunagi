import Foundation
import StudyCore
import SwiftUI

public struct FontLibraryView: View {
  @Bindable private var library: StudyFontLibrary
  @State private var confirmingDeletion = false
  public init(library: StudyFontLibrary) { self.library = library }
  public var body: some View {
    Form {
      Section {
        Text(
          "Choose the Japanese fonts to use in reviews. A selected font is chosen for each new subject. With none selected, reviews use the default Japanese font."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      ForEach(library.options) { font in
        Section {
          VStack(alignment: .leading, spacing: 12) {
            if font.fontName != nil {
              Toggle(
                font.title,
                isOn: Binding(
                  get: { library.selectedFiles.contains(font.id) },
                  set: { library.send(.select(font.id, $0)) })
              )
              .accessibilityIdentifier("font.selection.\(font.id)")
            } else {
              HStack {
                Text(font.title).font(.headline)
                Spacer()
                if font.progress != nil {
                  Button("Cancel", systemImage: "xmark.circle") { library.send(.cancel(font.id)) }
                    .accessibilityIdentifier("font.cancel.\(font.id)")
                } else {
                  Button(font.error == nil ? "Download" : "Retry", systemImage: "arrow.down.circle")
                  { library.send(.download(font.id)) }
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
              } else if let name = StudyFont.definitions.first(where: { $0.fileName == font.id })?
                .fontName
              {
                Image(name, bundle: .module).resizable().renderingMode(.template).scaledToFit()
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
      if library.canDelete {
        Section {
          Button("Delete all downloaded fonts", systemImage: "trash", role: .destructive) {
            confirmingDeletion = true
          }
          .accessibilityIdentifier("fonts.deleteAll")
          .confirmationDialog(
            "Delete all downloaded fonts?", isPresented: $confirmingDeletion,
            titleVisibility: .visible
          ) {
            Button("Delete downloaded fonts", role: .destructive) { library.send(.deleteAll) }
          } message: {
            Text(
              "Downloads will stop and your font selection will be cleared. Reviews will use the default Japanese font."
            )
          }
        }
      }
      if let deletionError = library.deletionError { Text(deletionError).foregroundStyle(.red) }
    }
    .formStyle(.grouped)
    .navigationTitle("Select Fonts").task { library.reloadSelection() }
  }
}
