// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Observation
import StudyCore
import StudyUI
import SwiftUI

extension Notification.Name {
  static let avatarCacheCleared = Notification.Name("avatarCacheCleared")
}

@MainActor @Observable final class SettingsNavigation {
  typealias Page = StudySettingsPage
  var path: [Page] = []
  let account = StudyShellState()
  var pendingReviews = 0
}

struct ApplicationSettings: View {
  @Bindable var navigation: SettingsNavigation
  let lessons: StudyLessonSettings
  let subjects: StudySubjectSettings
  let notificationSettings: StudyNotifications
  let back: () -> Void
  let fonts: () -> Void
  let offlineAudio: () -> Void
  let developer: () -> Void
  let appearanceChanged: (InterfaceStyle) -> Void
  @ArchivedPreference(Settings.$gravatarCustomEmail) private var email: String
  @ArchivedPreference(Settings.$interfaceStyle) private var appearance: InterfaceStyle
  @State private var confirmingLogout = false
  @Environment(\.displayScale) private var displayScale
  var body: some View {
    NavigationStack(path: $navigation.path) {
      StudySettingsView(
        account: navigation.account.username.isEmpty ? nil : navigation.account,
        destination: { $0 }
      ) {
        Button("Developer options", systemImage: "hammer", action: developer)
          .accessibilityIdentifier("settings.developer")
      } accountActions: {
        Button("Log out", role: .destructive) { confirmingLogout = true }
          .accessibilityIdentifier("settings.logout")
      }
      .toolbar {
        ToolbarItem(placement: .navigation) {
          Button("Back", systemImage: "chevron.backward", action: back)
            .accessibilityIdentifier("settings.back")
        }
      }
      .onAppear { updateAvatar() }
      .onChange(of: navigation.path) { _, path in if path.isEmpty { updateAvatar() } }
      .onChange(of: email) { _, _ in if navigation.path.isEmpty { updateAvatar() } }
      .onChange(of: displayScale) { _, _ in if navigation.path.isEmpty { updateAvatar() } }
      .navigationDestination(for: SettingsNavigation.Page.self) { page in
        switch page {
        case .appearance:
          AppearanceSettingsView(
            appearance: Binding(
              get: { appearance.nativeAppearance }, set: { appearance = InterfaceStyle($0) }),
            email: $email, notifications: notificationSettings
          )
          .onChange(of: appearance) { _, value in appearanceChanged(value) }
        case .lessons:
          LessonSettingsView(settings: lessons)
        case .reviews:
          ReviewSettings(
            fonts: fonts, offlineAudio: offlineAudio, appearanceChanged: appearanceChanged)
        case .subjects:
          SubjectSettingsView(
            settings: subjects,
            skipKanjiReadings: Binding(
              get: { Settings.skipKanjiReadings }, set: { Settings.skipKanjiReadings = $0 }))
        }
      }
      .alert("Log out?", isPresented: $confirmingLogout) {
        Button("Log out", role: .destructive) {
          NotificationCenter.default.post(name: .logout, object: nil)
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        if navigation.pendingReviews > 0 {
          Text(
            "\(navigation.pendingReviews) reviews have not synced. Logging out removes this account's local data. Sync first to preserve those answers."
          )
        }
      }
    }
    .tint(StudyPalette.radical)
  }
  private func updateAvatar() {
    navigation.account.avatar =
      navigation.account.username.isEmpty ? nil : currentUserProfileImageURL(scale: displayScale)
  }

}

/// Only legacy scene, navigation and service callbacks remain outside SwiftUI.
final class SettingsViewController: UIHostingController<ApplicationSettings?>, TKMViewController {
  private var services: TKMServices!
  private let state = SettingsNavigation()
  private let notifications = NotificationDispatcher()
  var canSwipeToGoBack: Bool { state.path.isEmpty }
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices) { self.services = services }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Settings"
    rootView = ApplicationSettings(
      navigation: state,
      lessons: services?.lessonSettings ?? StudyLessonSettings(store: LegacyLessonPreferences()),
      subjects: services?.subjectSettings
        ?? StudySubjectSettings(store: LegacySubjectPreferences()),
      notificationSettings: services?.notifications
        ?? StudyNotifications(preferences: LegacyNotificationPreferences()),
      back: { [weak self] in self?.navigationController?.popViewController(animated: true) },
      fonts: { [weak self] in
        guard let self else { return }
        let controller = FontsViewController(library: services.fontLibrary)
        pushLegacy(controller)
      },
      offlineAudio: { [weak self] in
        guard let self else { return }
        services.offlineAudio.queueDownloads()
        let controller = OfflineAudioViewController(library: services.audio)
        pushLegacy(controller)
      },
      developer: { [weak self] in
        guard let self else { return }
        pushLegacy(DeveloperOptionsViewController(services: services))
      },
      appearanceChanged: { [weak self] value in self?.view.window?.setInterfaceStyle(value) })
    for name in [Notification.Name.lccUserInfoChanged, .lccPendingItemsChanged] {
      notifications.add(name: name) { [weak self] _ in
        DispatchQueue.main.async { self?.reloadAccount() }
      }
    }
    notifications.add(name: .avatarCacheCleared) { [weak self] _ in
      Task { @MainActor [weak self] in self?.state.account.avatarRevision &+= 1 }
    }
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
    reloadAccount()
  }
  private func reloadAccount() {
    guard let client = services?.localCachingClient else {
      state.account.username = ""
      state.account.level = 0
      state.account.avatar = nil
      state.pendingReviews = 0
      return
    }
    let user = client.getUserInfo()
    state.account.username = user?.username ?? ""
    state.account.level = Int(user?.level ?? 0)
    state.account.avatar =
      state.account.username.isEmpty
      ? nil : currentUserProfileImageURL(scale: view.traitCollection.displayScale)
    state.pendingReviews = client.pendingProgressCount
  }
  private func pushLegacy(_ controller: UIViewController) {
    navigationController?.isNavigationBarHidden = false
    navigationItem.backButtonTitle = state.path.last?.rawValue ?? "Settings"
    navigationController?.pushViewController(controller, animated: true)
  }
}
