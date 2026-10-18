import Foundation
import StudyCore
import Testing

@Suite @MainActor struct StudySignInTests {
  @Test func defaultTokenValidationAndDisabledPasswordMode() async {
    var credentials: StudyCredentials?
    let model = StudySignIn { supplied in
      credentials = supplied
      return StudySignInAccount(token: "verified", email: "")
    }
    #expect(!model.canSubmit)
    model.token = " \n "
    #expect(!model.canSubmit)
    model.switchMethod()
    #expect(model.method == .token)
    model.token = "  token-with-whitespace\n"
    #expect(model.canSubmit)
    let result = await model.submit()
    #expect(result?.token == "verified" && result?.email == "")
    #expect(credentials == .token("token-with-whitespace"))
    #expect(!model.isBusy && model.error == nil)
  }

  @Test func forcedEmailAndExactPasswordCannotBeReplacedByADifferentDraft() async {
    var credentials: StudyCredentials?
    let model = StudySignIn(forcedEmail: "original@example.test", allowsPassword: true) {
      supplied in
      credentials = supplied
      return StudySignInAccount(token: "new", email: "original@example.test")
    }
    model.switchMethod()
    #expect(!model.canSubmit)
    model.email = "other@example.test"
    model.password = " password with spaces "
    #expect(model.canSubmit)
    #expect(await model.submit()?.email == "original@example.test")
    #expect(
      credentials == .password(email: "original@example.test", password: " password with spaces "))
    model.switchMethod()
    #expect(model.password == " password with spaces " && model.method == .token)
  }

  @Test func failureAndHibernationReleaseControlsAndRetryWithoutCredentials() async {
    var attempts = 0
    let model = StudySignIn { _ in
      attempts += 1
      if attempts == 1 { throw StudySignInError.hibernating }
      if attempts == 2 { throw StudySignInError.message("Rejected") }
      return StudySignInAccount(token: "verified", email: "")
    }
    model.token = "candidate"
    #expect(await model.submit() == nil)
    #expect(model.isHibernating && model.error != nil && model.canSubmit)
    #expect(await model.submit() == nil)
    #expect(!model.isHibernating && model.error == "Rejected" && !model.isBusy)
    #expect(await model.submit()?.token == "verified")
    #expect(model.error == nil && !model.isHibernating && attempts == 3)
  }

  @Test func overlappingSubmitAndMethodSwitchCannotStartAnotherRequest() async throws {
    let probe = SignInProbe()
    let model = StudySignIn(allowsPassword: true, authenticate: probe.authenticate)
    model.token = "first"
    let task = Task { await model.submit() }
    await probe.waitForRequests(1)
    #expect(model.isBusy && !model.canSubmit)
    model.token = "edited"
    model.switchMethod()
    #expect(model.method == .token)
    #expect(await model.submit() == nil && probe.credentials == [.token("first")])
    probe.finish(0, token: "first-verified")
    #expect(await task.value?.token == "first-verified")
    #expect(!model.isBusy)
  }

  @Test func cancellationRejectsLateSuccessAndLeavesANewerAttemptInControl() async throws {
    let probe = SignInProbe()
    let model = StudySignIn(authenticate: probe.authenticate)
    model.token = "old"
    model.password = "transient"
    let old = Task { await model.submit() }
    await probe.waitForRequests(1)
    model.cancel()
    #expect(!model.isBusy && model.token.isEmpty && model.password.isEmpty)
    model.token = "new"
    let current = Task { await model.submit() }
    await probe.waitForRequests(2)
    probe.finish(0, token: "stale")
    #expect(await old.value == nil && model.isBusy && model.error == nil)
    probe.finish(1, token: "accepted")
    #expect(await current.value?.token == "accepted" && !model.isBusy)
  }

  @Test func cancelledTaskAndCancelledServiceCannotPublishCredentialsOrErrors() async {
    let probe = SignInProbe()
    let model = StudySignIn(authenticate: probe.authenticate)
    model.token = "candidate"
    let task = Task { await model.submit() }
    await probe.waitForRequests(1)
    task.cancel()
    probe.finish(0, token: "ignored")
    #expect(await task.value == nil && !model.isBusy && model.error == nil)
    let cancelled = StudySignIn { _ in throw CancellationError() }
    cancelled.token = "candidate"
    #expect(await cancelled.submit() == nil && !cancelled.isBusy && cancelled.error == nil)
  }
}

@MainActor private final class SignInProbe {
  var credentials = [StudyCredentials]()
  private var continuations = [CheckedContinuation<StudySignInAccount, any Error>]()
  func authenticate(_ credentials: StudyCredentials) async throws -> StudySignInAccount {
    self.credentials.append(credentials)
    return try await withCheckedThrowingContinuation { continuations.append($0) }
  }
  func waitForRequests(_ count: Int) async {
    for _ in 0..<1000 {
      if continuations.count >= count { return }
      await Task.yield()
    }
    Issue.record("Sign-in request did not start")
  }
  func finish(_ index: Int, token: String) {
    continuations[index].resume(returning: StudySignInAccount(token: token, email: ""))
  }
}
