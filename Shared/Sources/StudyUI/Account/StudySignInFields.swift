import StudyCore
import SwiftUI

struct StudyTokenEntry: View {
  @Binding var token: String
  var body: some View {
    HStack {
      SecureField("API token", text: $token)
        .autocorrectionDisabled().submitLabel(.go).privacySensitive()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .accessibilityIdentifier("login.token")
      PasteButton(payloadType: String.self) { strings in
        if let text = strings.first { token = text }
      }.labelStyle(.iconOnly).accessibilityLabel("Paste API token")
        .accessibilityIdentifier("login.paste")
    }
    Link(
      "Create a token in WaniKani",
      destination: URL(string: "https://www.wanikani.com/settings/personal_access_tokens")!
    )
    .accessibilityIdentifier("login.createToken")
  }
}

/// Account fields share the same sign-in owner on every platform.
/// The host cancels the owner when its entire form disappears, not when rows scroll away.
struct StudySignInFields: View {
  @Bindable var model: StudySignIn
  var submitTitle = "Sign in"
  let signedIn: (String) -> Void
  var body: some View {
    Section("WaniKani account") {
      if let email = model.forcedEmail {
        Text("Reconnecting \(email)").foregroundStyle(.secondary).accessibilityIdentifier(
          "login.account")
      }
      StudyTokenEntry(token: $model.token)
      Button(action: submit) {
        HStack {
          Text(submitTitle)
          if model.isBusy { ProgressView().accessibilityLabel("Signing in") }
        }
      }.buttonStyle(.borderedProminent).disabled(!model.canSubmit).accessibilityIdentifier(
        "login.submit")
    }.disabled(model.isBusy).onSubmit(submit)
    if let error = model.error {
      Section("Unable to sign in") {
        Text(error).accessibilityIdentifier("login.error")
        if model.isHibernating {
          Link("Open WaniKani Website", destination: URL(string: "https://www.wanikani.com")!)
            .accessibilityIdentifier("login.reactivate")
        }
      }
    }
    Section {
      Link(
        "Privacy policy",
        destination: URL(string: "https://github.com/davidsansome/tsurukame/wiki/Privacy-Policy")!
      )
      .accessibilityIdentifier("login.privacy")
    } footer: {
      Text(
        "Use a personal API token from WaniKani. Read access is enough to connect; sending answers and notes also requires assignment, review and study-material write permissions. This app does not request your password."
      )
    }
  }
  private func submit() {
    Task { if let token = await model.submit() { signedIn(token) } }
  }
}
