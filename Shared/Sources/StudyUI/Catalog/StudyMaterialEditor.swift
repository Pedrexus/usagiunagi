import StudyCore
import SwiftUI

public struct StudyMaterialEditor<Version: Equatable & Sendable>: View {
  private enum Field: Hashable {
    case meaning, reading
    case synonym(UUID)
  }
  private struct Synonym: Identifiable {
    let id = UUID()
    var text: String
  }
  private let subject: CatalogSubject
  private let initial: StudyMaterialEdit<Version>
  private let visibleQuestions: Set<StudyQuestionKind>
  private let saveMessage: String
  private let saveDraft: @MainActor (StudyMaterial, Version?) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var meaningNote: String
  @State private var readingNote: String
  @State private var synonyms: [Synonym]
  @State private var busy = false
  @State private var error: String?
  @State private var conflict: StudyMaterialEdit<Version>?
  @State private var discard = false
  @State private var replace = false
  @FocusState private var focusedField: Field?

  public init(
    subject: CatalogSubject, initial: StudyMaterialEdit<Version>,
    visibleQuestions: Set<StudyQuestionKind> = [.meaning, .reading],
    saveMessage: String, save: @escaping @MainActor (StudyMaterial, Version?) async throws -> Void
  ) {
    self.subject = subject
    self.initial = initial
    self.visibleQuestions = visibleQuestions
    self.saveMessage = saveMessage
    self.saveDraft = save
    let material = initial.material
    _meaningNote = State(initialValue: material.meaningNoteText)
    _readingNote = State(initialValue: material.readingNote)
    _synonyms = State(initialValue: material.meaningSynonyms.map { Synonym(text: $0) })
  }

  private var material: StudyMaterial {
    changes.applying(to: initial.material)
  }
  private var changes: StudyMaterialChanges {
    var result = StudyMaterialChanges()
    if visibleQuestions.contains(.meaning) {
      result.meaningNote = meaningNote
      let values = synonyms.map(\.text)
      result.meaningSynonyms =
        values == initial.material.meaningSynonyms
        ? values
        : values.filter {
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    if visibleQuestions.contains(.reading) { result.readingNote = readingNote }
    return result
  }
  private var changed: Bool {
    material != initial.material
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              subject.japanese.isEmpty
                ? subject.summary.meaning : subject.japanese
            )
            .font(.title2)
            Text(saveMessage)
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        if initial.material.isExcluded {
          Label("Excluded from lessons and reviews", systemImage: "eye.slash")
        }
        if visibleQuestions.contains(.meaning) {
          Section("Meaning note") {
            TextEditor(text: $meaningNote).frame(minHeight: 90)
              .focused($focusedField, equals: .meaning)
              .accessibilityLabel("Meaning note").accessibilityIdentifier("material.meaningNote")
          }
        }
        if visibleQuestions.contains(.reading), !subject.readings.isEmpty || !readingNote.isEmpty {
          Section("Reading note") {
            TextEditor(text: $readingNote).frame(minHeight: 90)
              .focused($focusedField, equals: .reading)
              .accessibilityLabel("Reading note").accessibilityIdentifier("material.readingNote")
          }
        }
        if visibleQuestions.contains(.meaning) {
          Section {
            ForEach($synonyms) { $synonym in
              HStack {
                TextField("Synonym", text: $synonym.text, axis: .vertical)
                  .focused($focusedField, equals: .synonym(synonym.id))
                  .autocorrectionDisabled().accessibilityLabel("Meaning synonym")
                  .accessibilityIdentifier("material.synonym")
                Button("Remove synonym", systemImage: "minus.circle") {
                  synonyms.removeAll { $0.id == synonym.id }
                }.labelStyle(.iconOnly)
                  .accessibilityLabel(
                    synonym.text.isEmpty
                      ? "Remove empty synonym" : "Remove synonym: \(synonym.text)"
                  )
                  .accessibilityIdentifier("material.removeSynonym.\(synonym.id)")
              }
            }
            Button("Add synonym", systemImage: "plus") { synonyms.append(Synonym(text: "")) }
              .accessibilityIdentifier("material.addSynonym")
          } header: {
            Text("Meaning synonyms")
          } footer: {
            Text(
              "These are additional accepted meaning answers. Use a separate entry for each synonym."
            )
          }
        }
        if let conflict {
          Section("Saved version changed") {
            Text(
              "Your draft is still above. Compare it with the saved version before replacing it.")
            savedVersion(conflict.material)
            Button("Replace saved version with my draft") { replace = true }
          }
        }
        if busy { ProgressView("Saving") }
      }
      .formStyle(.grouped)
      .scrollDismissesKeyboard(.interactively)
      .accessibilityIdentifier("material.form")
      .safeAreaInset(edge: .bottom) {
        if let error {
          Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.bar)
        }
      }
      .disabled(busy)
      .navigationTitle("Notes and synonyms")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { if changed { discard = true } else { dismiss() } }.disabled(busy)
            .accessibilityIdentifier("material.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save(expectedVersion: initial.version) }
            .accessibilityIdentifier("material.save")
            .disabled(busy || conflict != nil)
        }
        #if os(iOS)
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }.accessibilityIdentifier("material.keyboardDone")
          }
        #endif
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
          if let conflict { save(expectedVersion: conflict.version) }
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
      if visibleQuestions.contains(.meaning) {
        Text("Meaning note").font(.headline)
        Text(material.meaningNoteText.isEmpty ? "No meaning note" : material.meaningNoteText)
      }
      if visibleQuestions.contains(.reading) {
        Text("Reading note").font(.headline)
        Text(material.readingNote.isEmpty ? "No reading note" : material.readingNote)
      }
      if visibleQuestions.contains(.meaning) {
        Text("Meaning synonyms").font(.headline)
        if material.meaningSynonyms.isEmpty { Text("No synonyms") }
        ForEach(Array(material.meaningSynonyms.enumerated()), id: \.offset) { _, text in Text(text)
        }
      }
    }.textSelection(.enabled)
  }

  private func save(expectedVersion: Version?) {
    guard !busy else { return }
    busy = true
    error = nil
    focusedField = nil
    let value = changes.applying(to: conflict?.material ?? initial.material)
    Task {
      defer { busy = false }
      do {
        try await saveDraft(value, expectedVersion)
        dismiss()
      } catch let conflict as StudyMaterialEditConflict<Version> {
        error =
          "Saved notes changed. Your draft is intact. Compare the saved version below."
        self.conflict = conflict.current
      } catch { self.error = error.localizedDescription }
    }
  }
}
