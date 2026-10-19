import Foundation
import StudyCore
import StudyTestSupport
import Testing

@Suite @MainActor struct StudySignInTests {
  @Test func tokenValidationNormalizesOnlySurroundingWhitespace() async {
    var received: String?
    let model = StudySignIn { received = $0 }
    #expect(!model.canSubmit)
    model.token = " \n "
    #expect(!model.canSubmit)
    model.token = "  token-with-whitespace\n"
    #expect(model.canSubmit)
    #expect(await model.submit() == "token-with-whitespace")
    #expect(received == "token-with-whitespace" && !model.isBusy && model.error == nil)
  }
  @Test func reconnectingAccountIsReadOnlyContextAndNotACredential() async {
    var received: String?
    let model = StudySignIn(forcedEmail: "original@example.test") { received = $0 }
    model.token = "candidate"
    #expect(await model.submit() == "candidate")
    #expect(model.forcedEmail == "original@example.test" && received == "candidate")
  }
  @Test func retryClearsHibernationAndPreviousErrors() async {
    var attempts = 0
    let model = StudySignIn { _ in
      attempts += 1
      if attempts == 1 { throw StudySignInError.hibernating }
      if attempts == 2 { throw StudySignInError.message("Rejected") }
    }
    model.token = "candidate"
    #expect(await model.submit() == nil)
    #expect(model.isHibernating && model.error != nil && model.canSubmit)
    #expect(await model.submit() == nil)
    #expect(!model.isHibernating && model.error == "Rejected" && !model.isBusy)
    #expect(await model.submit() == "candidate")
    #expect(model.error == nil && !model.isHibernating && attempts == 3)
  }
  @Test func overlappingSubmitCannotReplaceTheCapturedToken() async {
    let probe = SignInProbe()
    let model = StudySignIn(authenticate: probe.authenticate)
    model.token = "first"
    let task = Task { await model.submit() }
    await probe.waitForRequests(1)
    #expect(model.isBusy && !model.canSubmit)
    model.token = "edited"
    #expect(await model.submit() == nil && probe.tokens == ["first"])
    probe.finish(0)
    #expect(await task.value == "first" && !model.isBusy)
  }
  @Test func cancellationRejectsLateSuccessAndLeavesANewerAttemptInControl() async {
    let probe = SignInProbe()
    let model = StudySignIn(authenticate: probe.authenticate)
    model.token = "old"
    let old = Task { await model.submit() }
    await probe.waitForRequests(1)
    model.cancel()
    #expect(!model.isBusy && model.token.isEmpty)
    model.token = "new"
    let current = Task { await model.submit() }
    await probe.waitForRequests(2)
    probe.finish(0)
    #expect(await old.value == nil && model.isBusy && model.error == nil)
    probe.finish(1)
    #expect(await current.value == "new" && !model.isBusy)
  }
  @Test(arguments: [false, true])
  func cancellingTheFormOrItsCallerCancelsTheAuthenticationOperation(parent: Bool) async {
    let gate = StudyTaskGate()
    let model = StudySignIn { _ in
      await gate.pause()
      try Task.checkCancellation()
    }
    model.token = "candidate"
    let task = Task { await model.submit() }
    await gate.waitForEntry()
    if parent { task.cancel() } else { model.cancel() }
    await gate.waitForCancellation()
    await gate.resume()
    #expect(await task.value == nil && !model.isBusy && model.error == nil)
  }
  @Test func cancelledServiceDoesNotPublishAnError() async {
    let model = StudySignIn { _ in throw CancellationError() }
    model.token = "candidate"
    #expect(await model.submit() == nil && !model.isBusy && model.error == nil)
  }
}
@MainActor private final class SignInProbe {
  var tokens = [String]()
  private var continuations = [CheckedContinuation<Void, any Error>]()
  func authenticate(_ token: String) async throws {
    tokens.append(token)
    try await withCheckedThrowingContinuation { continuations.append($0) }
  }
  func waitForRequests(_ count: Int) async {
    for _ in 0..<1000 {
      if continuations.count >= count { return }
      await Task.yield()
    }
    Issue.record("Sign-in request did not start")
  }
  func finish(_ index: Int) { continuations[index].resume() }
}
