import Foundation
import Testing

@testable import Tsurukame

@Suite @MainActor struct StudyShellStateTests {
  @Test func repeatedAccountReportsDoNotReplaceOrReopenADismissedWarning() {
    let state = StudyShellState()
    state.reportAccountIssue(.unauthorized)
    state.reportAccountIssue(.hibernating)
    #expect(state.accountIssue == .unauthorized)
    state.accountIssue = nil
    state.reportAccountIssue(.unauthorized)
    state.reportAccountIssue(.hibernating)
    #expect(state.accountIssue == nil)
  }
  @Test func successfulReauthenticationResetsOnlyAccountWarningOwnership() {
    let state = StudyShellState()
    state.username = "Learner"
    state.level = 24
    state.reportAccountIssue(.unauthorized)
    state.accountRestored()
    #expect(state.accountIssue == nil && state.username == "Learner" && state.level == 24)
    state.reportAccountIssue(.hibernating)
    #expect(state.accountIssue == .hibernating)
  }
  @Test func warningDismissalDoesNotClearAnActiveRefreshOrItsProgress() {
    let state = StudyShellState()
    let progress = Progress(totalUnitCount: 4)
    progress.completedUnitCount = 1
    state.progress = progress
    state.reportAccountIssue(.hibernating)
    state.accountIssue = nil
    state.reportAccountIssue(.hibernating)
    #expect(state.accountIssue == nil && state.progress === progress)
    #expect(progress.completedUnitCount == 1)
  }
}
