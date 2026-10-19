import StudyCore
import SwiftUI

public struct StudyTokenEntry: View {
  @Binding var token: String
  public init(token: Binding<String>) { self._token = token }
  public var body: some View {
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

/// Shared fields for the standalone iOS sign-in and native account form.
/// The host cancels the owner when its entire form disappears, not when rows scroll away.
public struct StudySignInFields: View {
  @Bindable var model: StudySignIn
  let submitTitle: String
  let signedIn: (String) -> Void
  public init(
    model: StudySignIn, submitTitle: String = "Sign in", signedIn: @escaping (String) -> Void
  ) {
    self.model = model
    self.submitTitle = submitTitle
    self.signedIn = signedIn
  }
  public var body: some View {
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

public struct StudySignInView: View {
  let appName: String
  let model: StudySignIn
  let signedIn: (String) -> Void
  public init(appName: String, model: StudySignIn, signedIn: @escaping (String) -> Void) {
    self.appName = appName
    self.model = model
    self.signedIn = signedIn
  }
  public var body: some View {
    Form {
      Section {
        Text(appName).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
        Text("Sign in to your WaniKani account").foregroundStyle(.secondary)
      }
      StudySignInFields(model: model, signedIn: signedIn)
    }.formStyle(.grouped).tint(StudyPalette.radical).onDisappear { model.cancel() }
  }
}
