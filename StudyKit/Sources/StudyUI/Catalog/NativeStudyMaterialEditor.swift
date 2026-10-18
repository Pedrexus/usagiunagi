import StudyCore
import StudyPersistence
import SwiftUI

struct NativeStudyMaterialEditor: View {
  private struct Synonym: Identifiable {
    let id = UUID()
    var text: String
  }
  let store: StudyStore
  let accountID: String
  let details: StudySubjectDetails
  @Environment(\.dismiss) private var dismiss
  @State private var meaningNote: String
  @State private var readingNote: String
  @State private var synonyms: [Synonym]
  @State private var busy = false
  @State private var error: String?
  @State private var conflict: StudySubjectDetails?
  @State private var discard = false
  @State private var replace = false

  init(store: StudyStore, accountID: String, details: StudySubjectDetails) {
    self.store = store
    self.accountID = accountID
    self.details = details
    let material = details.material ?? StudyMaterial(subjectID: details.subject.id)
    _meaningNote = State(initialValue: material.meaningNote)
    _readingNote = State(initialValue: material.readingNote)
    _synonyms = State(initialValue: material.meaningSynonyms.map { Synonym(text: $0) })
  }

  private var material: StudyMaterial {
    StudyMaterial(
      subjectID: details.subject.id, meaningNote: meaningNote, readingNote: readingNote,
      meaningSynonyms: synonyms.map(\.text).filter {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
  }
  private var changed: Bool {
    material != (details.material ?? StudyMaterial(subjectID: details.subject.id))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            details.subject.japanese.isEmpty
              ? details.subject.summary.meaning : details.subject.japanese
          )
          .font(.title2)
          Text("Save keeps changes on this device. Send them to WaniKani from Saved work.")
            .foregroundStyle(.secondary)
        }
        Section("Meaning note") {
          TextEditor(text: $meaningNote).frame(minHeight: 90)
            .accessibilityLabel("Meaning note").accessibilityIdentifier("material.meaningNote")
        }
        if !details.subject.readings.isEmpty || !readingNote.isEmpty {
          Section("Reading note") {
            TextEditor(text: $readingNote).frame(minHeight: 90)
              .accessibilityLabel("Reading note").accessibilityIdentifier("material.readingNote")
          }
        }
        Section {
          ForEach($synonyms) { $synonym in
            HStack {
              TextField("Synonym", text: $synonym.text, axis: .vertical)
                .autocorrectionDisabled().accessibilityLabel("Meaning synonym")
              Button("Remove synonym", systemImage: "minus.circle") {
                synonyms.removeAll { $0.id == synonym.id }
              }.labelStyle(.iconOnly)
                .accessibilityLabel(
                  synonym.text.isEmpty ? "Remove empty synonym" : "Remove synonym: \(synonym.text)"
                )
                .accessibilityIdentifier("material.removeSynonym.\(synonym.id)")
            }
          }
          Button("Add synonym", systemImage: "plus") { synonyms.append(Synonym(text: "")) }
        } header: {
          Text("Meaning synonyms")
        } footer: {
          Text(
            "These are additional accepted meaning answers. Use a separate entry for each synonym.")
        }
        if let conflict {
          Section("Saved version changed") {
            Text(
              "Your draft is still above. Compare it with the saved version before replacing it.")
            savedVersion(conflict.material ?? StudyMaterial(subjectID: details.subject.id))
            Button("Replace saved version with my draft") { replace = true }
          }
        }
        if busy { ProgressView("Saving") }
      }
      .formStyle(.grouped)
      .safeAreaInset(edge: .bottom) {
        if let error {
          Text(error).foregroundStyle(.red).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.bar)
        }
      }
      .disabled(busy)
      .navigationTitle("Notes and synonyms")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { if changed { discard = true } else { dismiss() } }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save(expectedRevision: details.savedMaterial?.revision) }
            .disabled(busy || conflict != nil)
        }
      }
      .interactiveDismissDisabled(changed || busy)
      .confirmationDialog(
        "Discard your unsaved changes?", isPresented: $discard, titleVisibility: .visible
      ) {
        Button("Discard changes", role: .destructive) { dismiss() }
      }
      .confirmationDialog(
        "Replace the saved notes and synonyms?", isPresented: $replace, titleVisibility: .visible
      ) {
        Button("Replace with my draft", role: .destructive) {
          if let conflict { save(expectedRevision: conflict.savedMaterial?.revision) }
        }
      } message: {
        Text(
          "Your draft will replace the saved version shown here. A newer change will stop the save again."
        )
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, idealWidth: 560, minHeight: 560)
    #endif
  }

  private func savedVersion(_ material: StudyMaterial) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Meaning note").font(.headline)
      Text(material.meaningNote.isEmpty ? "No meaning note" : material.meaningNote)
      Text("Reading note").font(.headline)
      Text(material.readingNote.isEmpty ? "No reading note" : material.readingNote)
      Text("Meaning synonyms").font(.headline)
      if material.meaningSynonyms.isEmpty { Text("No synonyms") }
      ForEach(Array(material.meaningSynonyms.enumerated()), id: \.offset) { _, text in Text(text) }
    }.textSelection(.enabled)
  }

  private func save(expectedRevision: UUID?) {
    guard !busy else { return }
    busy = true
    error = nil
    let value = material
    Task {
      defer { busy = false }
      do {
        try await store.saveSubjectMaterial(
          value, accountID: accountID, expectedRevision: expectedRevision)
        dismiss()
      } catch StudyStoreError.staleMaterial {
        error =
          "These notes changed while you were editing. Your draft is intact. Compare the saved version below before replacing it."
        do {
          conflict = try await store.subjectDetails(
            subjectID: value.subjectID, accountID: accountID)
        } catch { self.error = error.localizedDescription }
      } catch { self.error = error.localizedDescription }
    }
  }
}
