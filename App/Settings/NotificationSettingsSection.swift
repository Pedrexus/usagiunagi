import StudyCore
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

struct NotificationSettingsSection: View {
  @Bindable var notifications: StudyNotifications
  @State private var notice: StudyNotifications.Notice?
  @State private var awaitingSettings: NotificationPermissionRequest?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  var body: some View {
    Section("Notifications") {
      ForEach(NotificationPreference.allCases) { option in
        Toggle(
          option.title,
          isOn: Binding(
            get: { notifications.enabled(option) },
            set: { value in
              Task {
                notice = await notifications.change(option, enabled: value)
              }
            })
        )
        .disabled(notifications.busy).accessibilityIdentifier("settings.\(option.key)")
      }
      if notifications.authorization == .notDetermined,
        NotificationPreference.allCases.contains(where: notifications.enabled)
      {
        Button("Allow notifications") {
          Task {
            notice = await notifications.requestAuthorizationIfNeeded()
          }
        }.disabled(notifications.busy)
      }
      if notifications.busy { ProgressView("Checking notification permission") }
      if let error = notifications.deliveryError {
        Label(error, systemImage: "exclamationmark.triangle").font(.callout)
        Button("Try again") { Task { await notifications.refresh() } }
      }
    }
    .task { await notifications.refresh() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await resumeIfNeeded() } }
    }
    .onChange(of: notifications.busy) { _, busy in
      if !busy, scenePhase == .active { Task { await resumeIfNeeded() } }
    }
    .alert(
      notice?.title ?? "Notifications",
      isPresented: Binding(
        get: { notice != nil }, set: { if !$0 { notice = nil } }), presenting: notice
    ) { value in
      switch value {
      case .systemSettings(let request):
        Button("Open Settings") {
          awaitingSettings = request
          #if os(iOS)
            openURL(URL(string: UIApplication.openSettingsURLString)!)
          #elseif os(macOS)
            if let url = NSWorkspace.shared.urlForApplication(
              withBundleIdentifier: "com.apple.systempreferences")
            {
              NSWorkspace.shared.open(url)
            }
          #endif
        }
        Button("Cancel", role: .cancel) { notifications.cancelSystemSettings(request) }
      case .error: Button("OK", role: .cancel) {}
      }
    } message: { value in
      Text(value.message)
    }
  }
  private func resumeIfNeeded() async {
    guard let request = awaitingSettings else { return }
    if await notifications.resumed(request), awaitingSettings?.id == request.id {
      awaitingSettings = nil
    }
  }

}
