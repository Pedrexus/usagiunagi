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
import StudyCore
import StudyUI
import SwiftUI
import WaniKaniAPI

extension Notification.Name {
  static let logout = Notification.Name("kLogoutNotification")
}

protocol LoginViewControllerDelegate: AnyObject { func loginComplete() }

final class LoginViewController: UIHostingController<StudySignInView?> {
  weak var delegate: LoginViewControllerDelegate?

  init(forcedEmail: String? = nil) {
    super.init(rootView: nil)
    let model = StudySignIn(
      forcedEmail: forcedEmail,
      allowsPassword: FeatureFlags.showUsernamePasswordLogin,
      authenticate: { credentials in try await Self.authenticate(credentials) })
    rootView = StudySignInView(appName: AppIdentity.name, model: model) { [weak self] account in
      guard let self else { return }
      Settings.userApiToken = account.token
      Settings.userEmailAddress = account.email
      self.delegate?.loginComplete()
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(forcedEmail:)") }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
  }

  @MainActor private static func authenticate(_ credentials: StudyCredentials) async throws
    -> StudySignInAccount
  {
    #if DEBUG
      if Screenshotter.isActive, ProcessInfo.processInfo.arguments.contains("LoginFlowFixture") {
        return try await LoginFixture.authenticate(credentials)
      }
    #endif
    do {
      return try await withCheckedThrowingContinuation { continuation in
        switch credentials {
        case .token(let token):
          WaniKaniAPIClient(apiToken: token, baseUrl: Settings.apiBaseUrl).user(
            progress: Progress()
          )
          .done { _ in continuation.resume(returning: StudySignInAccount(token: token, email: "")) }
          .catch { error in
            if let api = error as? WaniKaniAPIError, api.message?.contains("hibernating") == true {
              continuation.resume(throwing: StudySignInError.hibernating)
            } else {
              continuation.resume(throwing: error)
            }
          }
        case .password(let email, let password):
          WaniKaniWebClient().login(email: email, password: password)
            .done { result in
              continuation.resume(
                returning: StudySignInAccount(token: result.apiToken, email: email))
            }
            .catch { error in continuation.resume(throwing: error) }
        }
      }
    } catch WaniKaniWebClientError.accountHibernating { throw StudySignInError.hibernating }
  }
}
