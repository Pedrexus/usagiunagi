import Foundation
import SwiftUI

@Observable public final class StudyShellState {
  public enum AccountIssue { case unauthorized, hibernating }
  public var accountIssue: AccountIssue?
  private var accountIssueReported = false
  public func reportAccountIssue(_ issue: AccountIssue) {
    guard !accountIssueReported else { return }
    accountIssueReported = true
    accountIssue = issue
  }
  public func accountRestored() {
    accountIssue = nil
    accountIssueReported = false
  }
  public var username = ""
  public var level = 0
  public var learnedKanji: Int?
  public var avatar: URL?
  public var avatarRevision = 0
  public var progress: Progress?
  public init() {}
}

public struct StudyShellView<Content: View>: View {
  let state: StudyShellState
  let signIn: () -> Void
  let manageToken: (() -> Void)?
  let acknowledgeAccountIssue: () -> Void
  @State private var isVisible = false
  @Environment(\.openURL) private var openURL
  let content: Content

  public init(
    state: StudyShellState, signIn: @escaping () -> Void, manageToken: (() -> Void)?,
    acknowledgeAccountIssue: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.state = state
    self.signIn = signIn
    self.manageToken = manageToken
    self.acknowledgeAccountIssue = acknowledgeAccountIssue
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: 0) {
      if let progress = state.progress {
        ProgressView(progress).progressViewStyle(.linear).labelsHidden()
          .accessibilityLabel("WaniKani sync").accessibilityIdentifier("app.syncProgress")
      }
      content
    }.background(.background).tint(StudyPalette.radical)
      .onAppear { isVisible = true }
      .onDisappear { isVisible = false }
      .alert(
        state.accountIssue == .hibernating ? "Account is Hibernating" : "Logged out",
        isPresented: Binding(
          get: { isVisible && state.accountIssue != nil },
          set: { if !$0 && isVisible { state.accountIssue = nil } }),
        presenting: state.accountIssue
      ) { issue in
        switch issue {
        case .unauthorized:
          if let manageToken {
            Button("Manage tokens on WaniKani") {
              state.accountIssue = nil
              acknowledgeAccountIssue()
              manageToken()
            }
          }
          Button("OK") {
            state.accountIssue = nil
            acknowledgeAccountIssue()
            signIn()
          }
        case .hibernating:
          Button("Open WaniKani Website") {
            state.accountIssue = nil
            acknowledgeAccountIssue()
            openURL(URL(string: "https://www.wanikani.com")!)
          }
          Button("OK", role: .cancel) {
            state.accountIssue = nil
            acknowledgeAccountIssue()
          }
        }
      } message: { issue in
        Text(
          issue == .hibernating
            ? "Your WaniKani account is hibernating after a period of inactivity. Sign in on the WaniKani website to reactivate it."
            : "Your API token is invalid, expired or missing permissions. Sign in again to continue syncing. Your saved review progress is kept on this device.\n\nRequired permissions: assignments:start, reviews:create, study_materials:create and study_materials:update."
        )
      }
  }
}
