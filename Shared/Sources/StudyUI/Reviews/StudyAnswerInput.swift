import StudyCore
import SwiftUI

struct StudyAnswerInput {
  let prompt: String
  @Binding var text: String
  @Binding var focused: Bool
  let reading: Bool
  let automaticJapanese: Bool
  let editable: Bool
  let alphabet: KanaAlphabet
  let submitted: () -> Void
  let retried: () -> Void
  var accessibilityIdentifier = "review.answer"
  #if os(macOS)
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var inputFocused: Bool
  #endif
}

#if os(iOS)
  import UIKit

  /// The one UIKit boundary for Japanese input language and marked-text/caret handling.
  open class StudyJapaneseTextField: UITextField {
    public class var japaneseTextInputMode: UITextInputMode? {
      UITextInputMode.activeInputModes.first { $0.primaryLanguage?.hasPrefix("ja") == true }
    }
    public var useJapaneseKeyboard = false {
      didSet { if oldValue != useJapaneseKeyboard && isFirstResponder { reloadInputViews() } }
    }
    var wantsFocus = false
    open override func cut(_ sender: Any?) {
      guard (delegate as? StudyAnswerInput.Coordinator)?.parent.editable != false else { return }
      super.cut(sender)
    }
    open override func deleteBackward() {
      guard let coordinator = delegate as? StudyAnswerInput.Coordinator,
        !coordinator.parent.editable
      else {
        super.deleteBackward()
        return
      }
      coordinator.parent.retried()
    }
    open override var textInputContextIdentifier: String? {
      useJapaneseKeyboard ? "com.tsurukame.answer.ja" : "com.tsurukame.answer"
    }
    open override var textInputMode: UITextInputMode? {
      useJapaneseKeyboard ? Self.japaneseTextInputMode ?? super.textInputMode : super.textInputMode
    }
    open override func didMoveToWindow() {
      super.didMoveToWindow()
      Task { @MainActor [weak self] in
        guard let self, self.window != nil, self.wantsFocus, self.isEnabled, !self.isFirstResponder
        else { return }
        self.becomeFirstResponder()
      }
    }
  }

  extension StudyAnswerInput: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> StudyJapaneseTextField {
      let field = StudyJapaneseTextField(frame: .zero)
      field.delegate = context.coordinator
      field.addTarget(
        context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
      field.borderStyle = .roundedRect
      field.adjustsFontForContentSizeCategory = true
      field.textAlignment = .center
      field.autocapitalizationType = .none
      field.autocorrectionType = .no
      field.spellCheckingType = .no
      field.returnKeyType = .done
      field.accessibilityIdentifier = accessibilityIdentifier
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      return field
    }
    func updateUIView(_ field: StudyJapaneseTextField, context: Context) {
      context.coordinator.parent = self
      let font = UIFont.preferredFont(
        forTextStyle: context.environment.controlSize == .small ? .caption2 : .title2)
      if field.font != font { field.font = font }
      field.placeholder = prompt
      if field.text != text && field.markedTextRange == nil { field.text = text }
      let enabled = context.environment.isEnabled
      let japanese = automaticJapanese && reading
      field.wantsFocus = focused && enabled
      context.coordinator.configuration?.cancel()
      // Resigning during updateUIView asks the hosting graph for its next responder recursively.
      context.coordinator.configuration = Task { @MainActor [weak field] in
        guard !Task.isCancelled, let field else { return }
        if field.isEnabled != enabled { field.isEnabled = enabled }
        field.useJapaneseKeyboard = japanese
        guard field.window != nil else { return }
        if field.wantsFocus && !field.isFirstResponder {
          field.becomeFirstResponder()
        } else if !field.wantsFocus && field.isFirstResponder {
          field.resignFirstResponder()
        }
      }
    }
    static func dismantleUIView(_ field: StudyJapaneseTextField, coordinator: Coordinator) {
      coordinator.configuration?.cancel()
      field.wantsFocus = false
      field.delegate = nil
      Task { @MainActor [weak field] in field?.resignFirstResponder() }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
      var parent: StudyAnswerInput
      var configuration: Task<Void, Never>?
      init(_ parent: StudyAnswerInput) { self.parent = parent }
      @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
      func textField(
        _ field: UITextField, shouldChangeCharactersIn range: NSRange,
        replacementString value: String
      ) -> Bool {
        guard parent.editable else {
          if value.isEmpty { parent.retried() }
          return false
        }
        guard parent.reading, field.markedTextRange == nil,
          let edit = KanaConverter.edit(
            text: field.text ?? "", range: range,
            replacement: value, alphabet: parent.alphabet)
        else { return true }
        let selection = field.selectedTextRange
        field.text = edit.text
        if let cursor = edit.cursor,
          let position = field.position(from: field.beginningOfDocument, offset: cursor)
        {
          field.selectedTextRange = field.textRange(from: position, to: position)
        } else {
          field.selectedTextRange = selection
        }
        if !edit.allowsSystemChange { changed(field) }
        return edit.allowsSystemChange
      }
      func textFieldShouldReturn(_ field: UITextField) -> Bool {
        if field.markedTextRange == nil { parent.submitted() }
        return false
      }
      func textFieldDidBeginEditing(_ field: UITextField) { updateFocus(field) }
      func textFieldDidEndEditing(_ field: UITextField) { updateFocus(field) }
      private func updateFocus(_ field: UITextField) {
        guard field.isEnabled else { return }
        Task { @MainActor [weak field] in
          guard let field, field.isEnabled, self.parent.focused != field.isFirstResponder else {
            return
          }
          self.parent.focused = field.isFirstResponder
        }
      }
    }
  }

  struct StudyInputSettings: View {
    @Binding var automaticJapanese: Bool
    @State private var missingKeyboard = false
    var body: some View {
      Toggle(
        "Switch to Japanese keyboard",
        isOn: Binding(
          get: { automaticJapanese },
          set: { value in
            if value && StudyJapaneseTextField.japaneseTextInputMode == nil {
              missingKeyboard = true
            } else {
              automaticJapanese = value
            }
          })
      )
      .accessibilityIdentifier("settings.autoSwitchKeyboard")
      .alert("No Japanese keyboard", isPresented: $missingKeyboard) {
        Button("Close", role: .cancel) {}
      } message: {
        Text(
          "Add a Japanese keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard."
        )
      }
    }
  }
#else
  extension StudyAnswerInput: View {
    var body: some View {
      TextField(prompt, text: $text)
        .textFieldStyle(.roundedBorder).font(controlSize == .small ? .caption2 : .title2)
        .autocorrectionDisabled()
        .disabled(!editable)
        .focused($inputFocused).onSubmit(submitted)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onChange(of: focused && editable && isEnabled, initial: true) { _, value in
          if inputFocused != value { inputFocused = value }
        }
        .onChange(of: inputFocused) { _, value in
          guard editable, isEnabled else { return }
          if focused != value { focused = value }
        }
    }
  }
#endif
