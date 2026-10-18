// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Observation
import SwiftUI
import UserNotifications

enum NotificationPreference: String, CaseIterable, Identifiable {
  case reviews, badge, sound
  var id: Self { self }
  var title: String {
    switch self {
    case .reviews: "Notify for all available reviews"
    case .badge: "Badge the app icon"
    case .sound: "Play sound with notifications"
    }
  }
  var setting: Setting<Bool> {
    switch self {
    case .reviews: Settings.$notificationsAllReviews
    case .badge: Settings.$notificationsBadging
    case .sound: Settings.$notificationSounds
    }
  }
}

struct NotificationAuthorization {
  var status: @MainActor () async -> UNAuthorizationStatus
  var request: @MainActor () async throws -> Bool
  var clearBadge: @MainActor () async throws -> Void
  static var system: Self {
    .init(
      status: {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      },
      request: {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [
          .badge, .alert, .sound,
        ])
      },
      clearBadge: { try await UNUserNotificationCenter.current().setBadgeCount(0) })
  }
}

@MainActor @Observable final class NotificationPermissionModel {
  enum Notice {
    case systemSettings
    case error(String)
    var title: String {
      switch self {
      case .systemSettings: "Notifications are disabled"
      case .error: "Could not enable notifications"
      }
    }
    var message: String {
      switch self {
      case .systemSettings: "Allow notifications in system Settings, then return to the app."
      case .error(let message): message
      }
    }
  }
  private let client: NotificationAuthorization
  private var revision = 0
  private var pending: NotificationPreference?
  private(set) var busy = false
  var notice: Notice?
  init(client: NotificationAuthorization = .system) { self.client = client }
  func enabled(_ option: NotificationPreference) -> Bool {
    _ = revision
    return option.setting.wrappedValue
  }
  private func save(_ value: Bool, for option: NotificationPreference) {
    var setting = option.setting
    setting.wrappedValue = value
    revision &+= 1
  }
  func change(_ option: NotificationPreference, enabled: Bool) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    if !enabled {
      save(false, for: option)
      // Clearing a badge must not prevent saving an off preference if permission was revoked.
      try? await client.clearBadge()
      return
    }
    switch await client.status() {
    case .authorized, .provisional, .ephemeral: save(true, for: option)
    case .notDetermined:
      do { save(try await client.request(), for: option) } catch {
        save(false, for: option)
        notice = .error(error.localizedDescription)
      }
    case .denied:
      save(false, for: option)
      pending = option
      notice = .systemSettings
    @unknown default:
      save(false, for: option)
      notice = .error("Notification authorization is unavailable.")
    }
  }
  func cancelSystemSettings() { pending = nil }
  func resumed() async {
    guard let option = pending else { return }
    pending = nil
    notice = nil
    let status = await client.status()
    save(status == .authorized || status == .provisional || status == .ephemeral, for: option)
  }
}

struct AppearanceSettings: View {
  let appearanceChanged: (InterfaceStyle) -> Void
  @ArchivedPreference(Settings.$interfaceStyle) private var appearance: InterfaceStyle
  @ArchivedPreference(Settings.$gravatarCustomEmail) private var email: String
  @State private var notifications = NotificationPermissionModel()
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
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
      Section("Notifications") {
        ForEach(NotificationPreference.allCases) { option in
          Toggle(
            option.title,
            isOn: Binding(
              get: { notifications.enabled(option) },
              set: { value in
                Task { await notifications.change(option, enabled: value) }
              })
          )
          .disabled(notifications.busy)
          .accessibilityIdentifier("settings.\(option.setting.key)")
        }
        if notifications.busy { ProgressView("Checking notification permission") }
      }
    }
    .navigationTitle("Appearance")
    .scrollDismissesKeyboard(.interactively)
    .onChange(of: appearance) { _, value in appearanceChanged(value) }
    .onChange(of: scenePhase) { _, value in
      if value == .active { Task { await notifications.resumed() } }
    }
    .alert(
      notifications.notice?.title ?? "Notifications",
      isPresented: Binding(
        get: { notifications.notice != nil }, set: { if !$0 { notifications.notice = nil } }
      ), presenting: notifications.notice
    ) { notice in
      switch notice {
      case .systemSettings:
        Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
        Button("Cancel", role: .cancel) { notifications.cancelSystemSettings() }
      case .error: Button("OK", role: .cancel) {}
      }
    } message: { notice in
      Text(notice.message)
    }
  }
}
