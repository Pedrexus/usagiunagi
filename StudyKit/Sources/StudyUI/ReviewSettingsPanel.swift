import StudyCore
import SwiftUI

/// Native review preferences. The host handles persistence and the font library.
public struct ReviewSettingsPanel: View {
    @State private var preferences: ReviewPreferences
    private let changed: (ReviewPreferences, ReviewPreferences) -> Void
    private let fonts: () -> Void
    private let done: () -> Void

    public init(preferences: ReviewPreferences,
                changed: @escaping (ReviewPreferences, ReviewPreferences) -> Void,
                fonts: @escaping () -> Void, done: @escaping () -> Void) {
        _preferences = State(initialValue: preferences)
        self.changed = changed; self.fonts = fonts; self.done = done
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ReviewPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            let old = preferences
            preferences[keyPath: keyPath] = value
            changed(old, preferences)
        })
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Appearance", selection: binding(\.appearance)) {
                        Text("System").tag(ReviewPreferences.Appearance.system)
                        Text("Light").tag(ReviewPreferences.Appearance.light)
                        Text("Dark").tag(ReviewPreferences.Appearance.dark)
                    }.accessibilityIdentifier("reviewSettings.appearance")
                    Picker("SRS indicator", selection: binding(\.stageIndicator)) {
                        Text("Off").tag(ReviewPreferences.StageIndicator.none)
                        Text("Name").tag(ReviewPreferences.StageIndicator.name)
                        Text("Dots").tag(ReviewPreferences.StageIndicator.dots)
                    }.accessibilityIdentifier("reviewSettings.stage")
                    Picker("Japanese font size", selection: binding(\.fontScale)) {
                        ForEach(4...10, id: \.self) { step in
                            Text("\(step * 25)%").tag(Double(step) / 4)
                        }
                    }.accessibilityIdentifier("reviewSettings.fontSize")
                    Button("Japanese fonts", systemImage: "textformat") { fonts() }
                        .accessibilityIdentifier("reviewSettings.fonts")
                }
                Section("Answers and marking") {
                    Toggle("Autoreveal answers", isOn: binding(\.revealAnswers))
                        .accessibilityIdentifier("reviewSettings.autoreveal")
                    Toggle("Reveal full answer", isOn: binding(\.revealFullAnswer))
                        .accessibilityIdentifier("reviewSettings.fullAnswer")
                    Toggle("Exact match", isOn: binding(\.exactMatch))
                        .accessibilityIdentifier("reviewSettings.exactMatch")
                    Toggle("Allow answer corrections", isOn: binding(\.allowCorrections))
                        .accessibilityIdentifier("reviewSettings.corrections")
                    Toggle("Allow skipping", isOn: binding(\.allowSkipping))
                        .accessibilityIdentifier("reviewSettings.skipping")
                }
                Section("Audio") {
                    Toggle("Autoplay audio", isOn: binding(\.autoplayAudio))
                        .accessibilityIdentifier("reviewSettings.autoplay")
                    Toggle("Interrupt background audio", isOn: binding(\.interruptBackgroundAudio))
                        .accessibilityIdentifier("reviewSettings.interruptAudio")
                }
            }
            .navigationTitle("Quick settings")
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
