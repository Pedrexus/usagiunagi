// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyUI
import SwiftUI

struct AppearanceSettings: View {
  let appearanceChanged: (InterfaceStyle) -> Void
  @ArchivedPreference(Settings.$interfaceStyle) private var appearance: InterfaceStyle
  @ArchivedPreference(Settings.$gravatarCustomEmail) private var email: String
  let notifications: StudyNotifications
  var body: some View {
    Form {
      Section("UI appearance") {
        EnumSettingPicker(title: "Interface style", selection: $appearance)
          .accessibilityIdentifier("settings.interfaceStyle")
      }
      Section("Custom Gravatar email address") {
        TextField("Email address", text: $email)
          .submitLabel(.done)
          .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityIdentifier("settings.gravatarCustomEmail")
      }
      NotificationSettingsSection(notifications: notifications)
    }
    .navigationTitle("Appearance")
    .scrollDismissesKeyboard(.interactively)
    .onChange(of: appearance) { _, value in appearanceChanged(value) }
  }
}
