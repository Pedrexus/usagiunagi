import StudyCore
import SwiftUI

/// Native review preferences. The host handles persistence and the font library.
public struct ReviewSettingsPanel: View {
  @State private var preferences: ReviewPreferences
  private let sourcePreferences: ReviewPreferences
  private let changed: (ReviewPreferences, ReviewPreferences) -> Void
  private let fonts: (() -> Void)?
  private let offlineAudio: (() -> Void)?
  private let supportsAudio: Bool
  private let done: (() -> Void)?

  public init(
    preferences: ReviewPreferences,
    changed: @escaping (ReviewPreferences, ReviewPreferences) -> Void,
    fonts: (() -> Void)? = nil, offlineAudio: (() -> Void)? = nil, supportsAudio: Bool = true,
    done: (() -> Void)? = nil
  ) {
    _preferences = State(initialValue: preferences)
    sourcePreferences = preferences
    self.changed = changed
    self.fonts = fonts
    self.offlineAudio = offlineAudio
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
    Form {
      ReviewSettingsContent(
        preferences: binding, fonts: fonts, supportsAudio: supportsAudio,
        display: { EmptyView() }, answers: { EmptyView() },
        audio: {
          if let offlineAudio {
            Button("Offline Audio", systemImage: "arrow.down.circle", action: offlineAudio)
              .accessibilityIdentifier("reviewSettings.offlineAudio")
          }
        })
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
      if let done {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: done).accessibilityIdentifier("reviewSettings.done")
        }
      }
    }
  }
}

/// In-session preferences and media stay in one sheet; queue choices live in main settings.
public struct ReviewSettingsSheet: View {
  private enum Page: Hashable { case fonts, offlineAudio }
  private let preferences: ReviewPreferences
  private let changed: (ReviewPreferences, ReviewPreferences) -> Void
  private let fonts: StudyFontLibrary
  private let audio: StudyAudioLibrary?
  private let done: () -> Void
  @State private var path: [Page] = []
  public init(
    preferences: ReviewPreferences,
    changed: @escaping (ReviewPreferences, ReviewPreferences) -> Void,
    fonts: StudyFontLibrary, audio: StudyAudioLibrary? = nil, done: @escaping () -> Void
  ) {
    self.preferences = preferences
    self.changed = changed
    self.fonts = fonts
    self.audio = audio
    self.done = done
  }
  public var body: some View {
    NavigationStack(path: $path) {
      ReviewSettingsPanel(
        preferences: preferences, changed: changed,
        fonts: { path.append(.fonts) },
        offlineAudio: audio == nil ? nil : { path.append(.offlineAudio) }, done: done
      )
      .navigationDestination(for: Page.self) { page in
        Group {
          switch page {
          case .fonts: FontLibraryView(library: fonts)
          case .offlineAudio: if let audio { AudioLibraryView(library: audio) }
          }
        }.toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: done).accessibilityIdentifier("reviewSettings.done")
          }
        }
      }
    }
    .presentationSizing(.form)
    #if os(macOS)
      .frame(minWidth: 380, minHeight: 460)
    #endif
  }
}
