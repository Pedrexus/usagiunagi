import StudyCore
import SwiftUI

/// Native review preferences. The host handles persistence and the font library.
public struct ReviewSettingsPanel: View {
  @State private var preferences: ReviewPreferences
  private let sourcePreferences: ReviewPreferences
  private let changed: (ReviewPreferences, ReviewPreferences) -> Void
  private let fonts: (() -> Void)?
  private let supportsAudio: Bool
  private let done: () -> Void

  public init(
    preferences: ReviewPreferences,
    changed: @escaping (ReviewPreferences, ReviewPreferences) -> Void,
    fonts: (() -> Void)? = nil, supportsAudio: Bool = true, done: @escaping () -> Void
  ) {
    _preferences = State(initialValue: preferences)
    sourcePreferences = preferences
    self.changed = changed
    self.fonts = fonts
    self.supportsAudio = supportsAudio
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
    NavigationStack {
      Form {
        ReviewSettingsContent(
          preferences: binding, fonts: fonts, supportsAudio: supportsAudio,
          display: { EmptyView() }, answers: { EmptyView() }, audio: { EmptyView() })
      }
      #if os(macOS)
        .formStyle(.grouped)
      #endif
      .navigationTitle("Quick settings")
      .onChange(of: sourcePreferences) { _, value in preferences = value }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: done).accessibilityIdentifier("reviewSettings.done")
        }
      }
    }
  }
}
