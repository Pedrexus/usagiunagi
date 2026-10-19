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
import StudyCore
import StudyUI
import SwiftUI

extension Notification.Name {
  static let logout = Notification.Name("kLogoutNotification")
}

protocol LoginViewControllerDelegate: AnyObject { func loginComplete() }

final class LoginViewController: UIHostingController<StudySignInView?> {
  weak var delegate: LoginViewControllerDelegate?

  init(forcedEmail: String? = nil, reauthenticating services: TKMServices? = nil) {
    super.init(rootView: nil)
    let client = services?.localCachingClient
    let expected = Self.identity(client)
    let model = StudySignIn(forcedEmail: forcedEmail) { token in
      let account = try await Self.account(token)
      try Task.checkCancellation()
      if let services {
        guard let client, services.localCachingClient === client, let expected,
          let current = Self.identity(client), current.username == expected.username,
          current.startedAt == expected.startedAt
        else { throw StudySignInError.accountChanged }
        try account.requireLegacyAccount(expected)
      }
      Settings.userApiToken = token
      Settings.userEmailAddress = forcedEmail ?? ""
    }
    rootView = StudySignInView(appName: AppIdentity.name, model: model) { [weak self] _ in
      guard let self else { return }
      self.delegate?.loginComplete()
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(forcedEmail:)") }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
  }

  private static func identity(_ client: LocalCachingClient?) -> StudyAccountProfile? {
    guard let user = client?.getUserInfo() else { return nil }
    var profile = StudyAccountProfile(username: user.username)
    profile.startedAt = user.hasStartedAt ? Int64(user.startedAt) : nil
    return profile
  }
  @MainActor private static func account(_ token: String) async throws -> WaniKaniAccount {
    #if DEBUG
      if Screenshotter.isActive,
        ["LoginFlowFixture", "ReauthFlowFixture"].contains(
          where: ProcessInfo.processInfo.arguments.contains)
      {
        return try await LoginFixture.account(token)
      }
    #endif
    guard let endpoint = URL(string: Settings.apiBaseUrl) else {
      throw WaniKaniClient.APIError.invalidResponse
    }
    return try await WaniKaniClient(baseURL: endpoint).account(token: token)
  }
}
