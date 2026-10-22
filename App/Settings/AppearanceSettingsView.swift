import StudyCore
import SwiftUI

struct StudyAppearancePicker: View {
  var title = "Appearance"
  @Binding var selection: ReviewPreferences.Appearance
  var body: some View {
    Picker(title, selection: $selection) {
      Text("System").tag(ReviewPreferences.Appearance.system)
      Text("Light").tag(ReviewPreferences.Appearance.light)
      Text("Dark").tag(ReviewPreferences.Appearance.dark)
    }
  }
}

struct AppearanceSettingsView: View {
  @Binding var appearance: ReviewPreferences.Appearance
  @Binding var email: String
  let notifications: StudyNotifications?
  var body: some View {
    Form {
      Section("UI appearance") {
        StudyAppearancePicker(title: "Interface style", selection: $appearance)
          .accessibilityIdentifier("settings.interfaceStyle")
      }
      Section("Custom Gravatar email address") {
        TextField("Email address", text: $email).submitLabel(.done)
          #if os(iOS)
            .keyboardType(.emailAddress).textInputAutocapitalization(.never)
          #endif
          .autocorrectionDisabled().accessibilityIdentifier("settings.gravatarCustomEmail")
      }
      if let notifications { NotificationSettingsSection(notifications: notifications) }
    }.formStyle(.grouped).navigationTitle("Appearance").scrollDismissesKeyboard(.interactively)
  }
}
