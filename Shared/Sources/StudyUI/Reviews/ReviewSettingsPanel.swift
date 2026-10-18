import StudyCore
import SwiftUI

/// Native review preferences. The host handles persistence and the font library.
public struct ReviewSettingsPanel: View {
  @State private var preferences: ReviewPreferences
  private let sourcePreferences: ReviewPreferences
  private let changed: (ReviewPreferences, ReviewPreferences) -> Void
  private let fonts: (() -> Void)?
  private let supportsAudio: Bool
  private let supportsSessionOptions: Bool
  private let done: (() -> Void)?

  public init(
    preferences: ReviewPreferences,
    changed: @escaping (ReviewPreferences, ReviewPreferences) -> Void,
    fonts: (() -> Void)? = nil, supportsAudio: Bool = true, supportsSessionOptions: Bool = false,
    done: (() -> Void)? = nil
  ) {
    _preferences = State(initialValue: preferences)
    sourcePreferences = preferences
    self.changed = changed
    self.fonts = fonts
    self.supportsAudio = supportsAudio
    self.supportsSessionOptions = supportsSessionOptions
    self.done = done
  }

  private var binding: Binding<ReviewPreferences> {
    Binding(
      get: { preferences },
      set: { value in
        let old = preferences
        preferences = value
        changed(old, preferences)
      })
  }

  public var body: some View {
    Form {
      if supportsSessionOptions { StudySessionSettingsContent(options: binding.sessionOptions) }
      ReviewSettingsContent(
        preferences: binding, fonts: fonts, supportsAudio: supportsAudio,
        display: { EmptyView() }, answers: { EmptyView() }, audio: { EmptyView() })
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .navigationTitle(supportsSessionOptions ? "Review settings" : "Quick settings")
    .onChange(of: sourcePreferences) { _, value in preferences = value }
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      if let done {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: done).accessibilityIdentifier("reviewSettings.done")
        }
      }
    }
  }
}
