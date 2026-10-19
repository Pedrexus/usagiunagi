#if DEBUG
  import Foundation
  import PromiseKit
  import StudyCore

  /// Login navigation uses synthetic content and never clears the simulator's study database.
  class LoginFixtureCachingClient: FakeLocalCachingClient {
    override func clearAllData() {}
    override func clearAllDataAndClose() {}
  }

  final class AccountIssueFixtureCachingClient: LoginFixtureCachingClient {
    private var scheduled = false
    override func sync(quick: Bool, progress: Progress) -> PMKFinalizer {
      progress.totalUnitCount = 1
      progress.completedUnitCount = 1
      if !scheduled {
        scheduled = true
        let arguments = ProcessInfo.processInfo.arguments
        let name: Notification.Name =
          arguments.contains("HibernationFixture") ? .lccHibernating : .lccUnauthorized
        let delay = arguments.contains("DeferredAccountIssue") ? 8.0 : 1.0
        for offset in [0.0, 0.4, 0.8] {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay + offset) {
            NotificationCenter.default.post(name: name, object: nil)
          }
        }
      }
      return Promise.value(()).cauterize()
    }
  }

  @MainActor enum LoginFixture {
    static func authenticate(_ token: String) async throws {
      try await Task.sleep(for: .milliseconds(400))
      switch token {
      case "hibernating": throw StudySignInError.hibernating
      case "fixture-token": return
      default: throw StudySignInError.message("The fixture credentials were rejected.")
      }
    }
  }
#endif
