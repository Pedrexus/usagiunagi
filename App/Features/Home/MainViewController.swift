// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PromiseKit
import StudyUI
import SwiftUI
import WaniKaniAPI

private let kDefaultProfileImageURL =
  "https://cdn.wanikani.com/default-avatar-300x300-20121121.png"
private let kProfileImageSize: CGFloat = 80

// The user's Gravatar, or WaniKani's default avatar if they haven't given an email address.
func currentUserProfileImageURL() -> URL {
  let email =
    Settings.gravatarCustomEmail.isEmpty
    ? Settings.userEmailAddress : Settings.gravatarCustomEmail
  return email.isEmpty
    ? URL(string: kDefaultProfileImageURL)!
    : userProfileImageURL(emailAddress: email)
}

private func userProfileImageURL(emailAddress: String) -> URL {
  let address = emailAddress.trimmingCharacters(in: .whitespaces).lowercased()
  // Gravatar asks for an SHA-256 hash: https://docs.gravatar.com/general/hash/
  let hash = address.sha256()

  let size = kProfileImageSize * UIScreen.main.scale

  return URL(
    string: "https://www.gravatar.com/avatar/\(hash).jpg?s=\(size)&d=\(kDefaultProfileImageURL)")!
}

final class MainViewController: UIHostingController<MainShellRoot?>, LoginViewControllerDelegate,
  SearchResultViewControllerDelegate, MainWaniKaniTabViewController.Delegate
{
  var services: TKMServices!
  var onFirstAppearance: (() -> Void)?

  private let shell = StudyShellState()
  private var avatarRequest: URL?
  private var avatarRestoreTask: Task<Void, Never>?
  var searchResultsViewController: SearchResultViewController!
  private(set) var homeViewController: MainWaniKaniTabViewController?

  var hourlyRefreshTimer = Timer()
  var isUpdating = false

  private let nd = NotificationDispatcher()
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }

  func setup(services: TKMServices) {
    self.services = services
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let search = StoryboardScene.SearchResult.initialScene.instantiate()
    search.setup(services: services, delegate: self)
    searchResultsViewController = search
    let home = StoryboardScene.Main.home.instantiate()
    home.setup(services: services, delegate: self)
    homeViewController = home
    let practice =
      FeatureFlags.showOtherPracticeModes ? StoryboardScene.Main.practice.instantiate() : nil
    practice?.setup(services: services)
    rootView = MainShellRoot(
      state: shell, home: home, practice: practice,
      statistics: StatisticsViewController(services: services),
      search: { [weak self] in self?.searchButtonTapped() },
      settings: { [weak self] in self?.settingsButtonTapped() },
      signIn: { [weak self] in self?.loginAgain() },
      manageToken: Settings.userApiToken.isEmpty
        ? nil
        : { [weak self] in
          self?.loginAgain()
          UIApplication.shared.open(
            URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!)
        })
    updateHourlyTimer()
    updateHome()
    nd.add(name: .lccAvailableItemsChanged) { [weak self] _ in self?.availableItemsChanged() }
    nd.add(name: .lccRecentMistakesCountChanged) { [weak self] _ in self?.availableItemsChanged() }
    nd.add(name: .lccUserInfoChanged) { [weak self] _ in self?.userInfoChanged() }
    nd.add(name: .lccSRSCategoryCountsChanged) { [weak self] _ in self?.srsLevelCountsChanged() }
    nd.add(name: .lccUnauthorized) { [weak self] _ in self?.clientIsUnauthorized() }
    nd.add(name: .lccHibernating) { [weak self] _ in self?.clientIsHibernating() }
    nd.add(name: .avatarCacheCleared) { [weak self] _ in
      guard let self else { return }
      self.avatarRestoreTask?.cancel()
      self.avatarRequest = nil
      self.shell.avatar = nil
      self.shell.avatarRevision += 1
      self.updateUserInfo()
    }
    nd.add(name: UIApplication.didEnterBackgroundNotification) { [weak self] _ in
      self?.applicationDidEnterBackground()
    }
    nd.add(name: UIApplication.willEnterForegroundNotification) { [weak self] _ in
      self?.applicationWillEnterForeground()
    }
  }

  private func scheduleHomeUpdate() {
    if isUpdating {
      return
    }
    isUpdating = true

    DispatchQueue.main.async {
      WatchHelper.sharedInstance.updatedData(client: self.services.localCachingClient)
      self.isUpdating = false
      self.updateHome()
    }
  }

  private func updateHome() {
    updateUserInfo()

    homeViewController?.update()
  }

  // MARK: - UIViewController

  override func viewWillAppear(_ animated: Bool) {
    // Assume the hour changed while the view was invisible. This will invalidate the upcoming
    // review cache which depends on the current time.
    services.localCachingClient.currentHourChanged()

    updateHourlyTimer()

    navigationController?.isNavigationBarHidden = true

    super.viewWillAppear(animated)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Only start refreshing after the user has finished swiping back to this view.
    refresh(quick: true)
    let action = onFirstAppearance
    onFirstAppearance = nil
    action?()
  }

  override func viewWillDisappear(_ animated: Bool) {
    navigationController?.setNavigationBarHidden(false, animated: animated)
    super.viewWillDisappear(animated)
    cancelHourlyTimer()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    .default
  }

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    switch StoryboardSegue.Main(segue) {
    case .settings:
      let vc = segue.destination as! SettingsViewController
      vc.setup(services: services)

    default:
      break
    }
  }

  // MARK: - Navigation bar buttons

  func searchButtonTapped() {
    navigationController?.pushViewController(searchResultsViewController, animated: true)
  }

  func settingsButtonTapped() {
    perform(segue: StoryboardSegue.Main.settings, sender: self)
  }

  // MARK: - Refresh on the hour in the foreground

  func updateHourlyTimer() {
    cancelHourlyTimer()

    let calendar = Calendar.current as NSCalendar
    let date =
      calendar
      .nextDate(after: Date(), matching: .minute, value: 0, options: .matchNextTime)!

    hourlyRefreshTimer = Timer.scheduledTimer(
      withTimeInterval: date.timeIntervalSinceNow,
      repeats: false,
      block: { [weak self] _ in
        guard let self = self else { return }
        self.hourlyTimerExpired()
      })
  }

  func cancelHourlyTimer() {
    hourlyRefreshTimer.invalidate()
    hourlyRefreshTimer = Timer()
  }

  func hourlyTimerExpired() {
    services.localCachingClient.currentHourChanged()
    refresh(quick: true)
    updateHourlyTimer()
  }

  func applicationDidEnterBackground() {
    cancelHourlyTimer()
  }

  func applicationWillEnterForeground() {
    // Assume the hour changed while the application was in the background. This will invalidate the
    // upcoming review cache which depends on the current time.
    services.localCachingClient.currentHourChanged()

    updateHourlyTimer()
  }

  // MARK: - Refreshing contents

  func refresh(quick: Bool) {
    guard let client = services.localCachingClient else { return }
    let progress = Progress(totalUnitCount: 0)
    let completion = client.sync(quick: quick, progress: progress)
    if quick { scheduleHomeUpdate() }
    guard !progress.isFinished else { return }
    shell.progress = progress
    if !quick { shell.blockingProgress = progress }
    completion.finally { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.services.localCachingClient === client else { return }
        if self.shell.progress === progress { self.shell.progress = nil }
        if self.shell.blockingProgress === progress { self.shell.blockingProgress = nil }
        if progress.isFinished { self.services.radicalCharacterImages.downloadAll() }
      }
    }
  }

  func availableItemsChanged() {
    if (view?.window) != nil {
      scheduleHomeUpdate()
    }
  }

  func userInfoChanged() {
    updateUserInfo()
  }

  func updateUserInfo() {
    guard let client = services.localCachingClient, let user = client.getUserInfo() else { return }
    shell.username = user.username
    shell.level = Int(user.level)
    shell.learnedKanji = client.guruKanjiCount
    let avatar = currentUserProfileImageURL()
    if avatarRequest != avatar {
      avatarRequest = avatar
      avatarRestoreTask?.cancel()
      avatarRestoreTask = Task { @MainActor [weak self, legacy = services.legacyAvatars] in
        await legacy.restore(avatar)
        guard let self, !Task.isCancelled, self.services.localCachingClient === client,
          self.avatarRequest == avatar
        else { return }
        self.shell.avatar = avatar
      }
    }
    shell.onVacation = user.hasVacationStartedAt
  }

  func srsLevelCountsChanged() {
    if (view?.window) != nil {
      updateUserInfo()
      scheduleHomeUpdate()
    }
  }

  func clientIsUnauthorized() { shell.reportAccountIssue(.unauthorized) }
  func clientIsHibernating() { shell.reportAccountIssue(.hibernating) }

  func loginAgain() {
    guard services.localCachingClient.getUserInfo() != nil else {
      return
    }

    let vc = LoginViewController(
      forcedEmail: Settings.userEmailAddress.isEmpty ? nil : Settings.userEmailAddress,
      reauthenticating: services)
    vc.delegate = self
    navigationController?.pushViewController(vc, animated: true)
  }

  func loginComplete() {
    services.localCachingClient.client.updateApiToken(Settings.userApiToken)
    navigationController?.popViewController(animated: true)
    shell.accountRestored()
  }

  // MARK: - MainWaniKaniTabViewController.Delegate

  func didPullToRefresh() {
    refresh(quick: false)
  }

  // MARK: - Search

  func searchResultSelected(subject: TKMSubject) {
    let vc = StoryboardScene.SubjectDetails.initialScene.instantiate()
    vc.setup(services: services, subject: subject)
    navigationController?.popViewController(animated: false)
    navigationController?.pushViewController(vc, animated: true)
  }
}

struct MainShellRoot: View {
  let state: StudyShellState
  let home: MainWaniKaniTabViewController
  let practice: MainPracticeTabViewController?
  let statistics: StatisticsViewController
  let search: () -> Void
  let settings: () -> Void
  let signIn: () -> Void
  let manageToken: (() -> Void)?
  private static var initial: StudyTab {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("ShowStatistics") { return .statistics }
    #endif
    return .home
  }
  @State private var selection = Self.initial
  var body: some View {
    StudyShellView(
      state: state, search: search, settings: settings, signIn: signIn, manageToken: manageToken
    ) {
      StudyTabs(selection: $selection, showsPractice: practice != nil) {
        ShellDestination(controller: home)
      } practice: {
        if let practice { ShellDestination(controller: practice) }
      } statistics: {
        ShellDestination(controller: statistics)
      }
    }.overlay {
      if let progress = state.blockingProgress { FullRefreshOverlayView(progress: progress) }
    }
  }
}

private struct ShellDestination<Controller: UIViewController>: UIViewControllerRepresentable {
  let controller: Controller
  func makeUIViewController(context: Context) -> Controller { controller }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.view.isUserInteractionEnabled = context.environment.isEnabled
  }
}
