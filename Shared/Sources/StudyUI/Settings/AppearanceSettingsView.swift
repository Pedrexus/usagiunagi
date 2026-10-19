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

public struct AppearanceSettingsView: View {
  @Binding private var appearance: ReviewPreferences.Appearance
  @Binding private var email: String
  private let notifications: StudyNotifications?
  public init(
    appearance: Binding<ReviewPreferences.Appearance>, email: Binding<String>,
    notifications: StudyNotifications?
  ) {
    _appearance = appearance
    _email = email
    self.notifications = notifications
  }
  public var body: some View {
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
