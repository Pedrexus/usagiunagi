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

  init(forcedEmail: String? = nil) {
    super.init(rootView: nil)
    let model = StudySignIn(forcedEmail: forcedEmail, authenticate: Self.authenticate)
    rootView = StudySignInView(appName: AppIdentity.name, model: model) { [weak self] token in
      guard let self else { return }
      Settings.userApiToken = token
      Settings.userEmailAddress = forcedEmail ?? ""
      self.delegate?.loginComplete()
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(forcedEmail:)") }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
  }

  @MainActor private static func authenticate(_ token: String) async throws {
    #if DEBUG
      if Screenshotter.isActive,
        ["LoginFlowFixture", "ReauthFlowFixture"].contains(
          where: ProcessInfo.processInfo.arguments.contains)
      {
        try await LoginFixture.authenticate(token)
        return
      }
    #endif
    guard let endpoint = URL(string: Settings.apiBaseUrl) else {
      throw WaniKaniClient.APIError.invalidResponse
    }
    _ = try await WaniKaniClient(baseURL: endpoint).account(token: token)
  }
}
