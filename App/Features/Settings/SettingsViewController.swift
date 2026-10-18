// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Observation
import StudyUI
import SwiftUI

extension Notification.Name {
  static let avatarCacheCleared = Notification.Name("avatarCacheCleared")
}

@MainActor @Observable final class SettingsNavigation {
  enum Page: String, Hashable, CaseIterable {
    case appearance = "Appearance & Notifications"
    case lessons = "Lessons"
    case reviews = "Reviews"
    case subjects = "Radicals, Kanji & Vocabulary"
    var symbol: String {
      switch self {
      case .appearance: "bell.badge"
      case .lessons: "book"
      case .reviews: "rectangle.and.pencil.and.ellipsis"
      case .subjects: "character.book.closed"
      }
    }
  }
  var path: [Page] = []
  var username = ""
  var level = 0
  var pendingReviews = 0
  var avatarRevision = 0
}

struct ApplicationSettings: View {
  @Bindable var navigation: SettingsNavigation
  let back: () -> Void
  let fonts: () -> Void
  let offlineAudio: () -> Void
  let developer: () -> Void
  let appearanceChanged: (InterfaceStyle) -> Void
  @ArchivedPreference(Settings.$gravatarCustomEmail) private var email: String
  @State private var confirmingLogout = false
  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return
      "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
  }
  var body: some View {
    NavigationStack(path: $navigation.path) {
      Form {
        if !navigation.username.isEmpty {
          Section {
            HStack(spacing: 14) {
              AsyncImage(url: currentUserProfileImageURL()) { image in
                image.resizable().scaledToFill()
              } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
              }
              .frame(width: 52, height: 52).clipShape(Circle()).id(email).id(
                navigation.avatarRevision)
              VStack(alignment: .leading, spacing: 4) {
                Text(navigation.username).font(.headline)
                Text("Level \(navigation.level) · WaniKani").font(.subheadline).foregroundStyle(
                  .secondary)
              }
            }.padding(.vertical, 8)
          }
        }
        Section("Settings") {
          ForEach(SettingsNavigation.Page.allCases, id: \.self) { page in
            NavigationLink(value: page) { Label(page.rawValue, systemImage: page.symbol) }
              .accessibilityIdentifier("settings.page.\(page)")
          }
        }
        Section("Diagnostics") {
          LabeledContent("Version") { Text(version).textSelection(.enabled) }
            .contextMenu {
              Button("Copy version", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = version
              }
            }
          Button("Developer options", systemImage: "hammer", action: developer)
            .accessibilityIdentifier("settings.developer")
        }
        Section {
          Button("Log out", role: .destructive) { confirmingLogout = true }
            .accessibilityIdentifier("settings.logout")
        }
        Section {
          Link(
            destination: URL(
              string:
                "https://github.com/Pedrexus/usagiunagi/issues/new?title=Visual%20redesign%20feedback"
            )!
          ) {
            Label("Give feedback on the new app look", systemImage: "bubble.left")
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .navigation) {
          Button("Back", systemImage: "chevron.backward", action: back)
            .accessibilityIdentifier("settings.back")
        }
      }
      .navigationDestination(for: SettingsNavigation.Page.self) { page in
        switch page {
        case .appearance: AppearanceSettings(appearanceChanged: appearanceChanged)
        case .lessons: LessonSettings()
        case .reviews:
          ReviewSettings(
            fonts: fonts, offlineAudio: offlineAudio, appearanceChanged: appearanceChanged)
        case .subjects: SubjectDisplaySettings()
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
      Task { @MainActor [weak self] in self?.state.avatarRevision &+= 1 }
    }
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
    reloadAccount()
  }
  private func reloadAccount() {
    guard let client = services?.localCachingClient else {
      state.username = ""
      state.level = 0
      state.pendingReviews = 0
      return
    }
    let user = client.getUserInfo()
    state.username = user?.username ?? ""
    state.level = Int(user?.level ?? 0)
    state.pendingReviews = client.pendingProgressCount
  }
  private func pushLegacy(_ controller: UIViewController) {
    navigationController?.isNavigationBarHidden = false
    navigationItem.backButtonTitle = state.path.last?.rawValue ?? "Settings"
    navigationController?.pushViewController(controller, animated: true)
  }
}
