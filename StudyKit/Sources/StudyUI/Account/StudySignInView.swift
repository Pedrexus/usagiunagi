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

public struct StudySignInView: View {
  let appName: String
  @Bindable var model: StudySignIn
  let signedIn: (StudySignInAccount) -> Void
  @FocusState private var emailFocused: Bool
  @FocusState private var passwordFocused: Bool

  public init(appName: String, model: StudySignIn, signedIn: @escaping (StudySignInAccount) -> Void)
  {
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
      Section("Sign in") {
        if model.method == .token {
          StudyTokenEntry(token: $model.token)
        } else {
          TextField("Email", text: $model.email).textContentType(.username)
            .autocorrectionDisabled().focused($emailFocused).submitLabel(.next)
            #if os(iOS)
              .textInputAutocapitalization(.never).keyboardType(.emailAddress)
            #endif
            .disabled(model.forcedEmail != nil).accessibilityIdentifier("login.email")
            .onSubmit { passwordFocused = true }
          SecureField("Password", text: $model.password).textContentType(.password)
            .focused($passwordFocused).submitLabel(.go).privacySensitive()
            .accessibilityIdentifier("login.password").onSubmit(submit)
        }
        Button(action: submit) {
          HStack {
            Text("Sign in")
            if model.isBusy { ProgressView().accessibilityLabel("Signing in") }
          }
        }.buttonStyle(.borderedProminent).disabled(!model.canSubmit)
          .accessibilityIdentifier("login.submit")
        if model.allowsPassword {
          Button(model.method == .token ? "Use email and password" : "Use API token") {
            emailFocused = false
            passwordFocused = false
            model.switchMethod()
          }.accessibilityIdentifier("login.method")
        }
      }.disabled(model.isBusy)
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
          model.method == .password
            ? "Your password is used only to sign in to WaniKani and retrieve an API token. It is not saved by this app."
            : "Use an API token with assignment, review and study-material write permissions to study and sync."
        )
      }
    }.formStyle(.grouped).tint(StudyPalette.radical)
      .onSubmit { if model.method == .token { submit() } }
      .onDisappear { model.cancel() }
  }

  private func submit() {
    emailFocused = false
    passwordFocused = false
    Task { if let account = await model.submit() { signedIn(account) } }
  }
}
