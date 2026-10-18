#if DEBUG
  import Foundation
  import StudyCore

  /// Login navigation uses synthetic content and never clears the simulator's study database.
  final class LoginFixtureCachingClient: FakeLocalCachingClient {
    override func clearAllData() {}
    override func clearAllDataAndClose() {}
  }

  @MainActor enum LoginFixture {
    static func authenticate(_ credentials: StudyCredentials) async throws -> StudySignInAccount {
      try await Task.sleep(for: .milliseconds(400))
      switch credentials {
      case .token("hibernating"): throw StudySignInError.hibernating
      case .token("fixture-token"): return StudySignInAccount(token: "dummy", email: "")
      case .password(let email, "fixture-password"):
        return StudySignInAccount(token: "dummy", email: email)
      default: throw StudySignInError.message("The fixture credentials were rejected.")
      }
    }
  }
#endif
