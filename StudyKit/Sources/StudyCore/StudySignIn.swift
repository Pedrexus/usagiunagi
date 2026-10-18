import Foundation
import Observation

public enum StudyCredentials: Sendable, Equatable {
  case token(String)
  case password(email: String, password: String)
}

public struct StudySignInAccount: Sendable {
  public let token: String
  public let email: String
  public init(token: String, email: String) {
    self.token = token
    self.email = email
  }
}

public enum StudySignInError: LocalizedError {
  case hibernating
  case message(String)
  public var errorDescription: String? {
    switch self {
    case .hibernating:
      "Your WaniKani account is hibernating. Sign in on the WaniKani website to reactivate it."
    case .message(let message): message
    }
  }
}

@MainActor @Observable public final class StudySignIn {
  public enum Method { case token, password }
  public private(set) var method = Method.token
  public var token = ""
  public var email: String
  public var password = ""
  public let forcedEmail: String?
  public let allowsPassword: Bool
  public private(set) var isBusy = false
  public private(set) var error: String?
  public private(set) var isHibernating = false
  private var request: UUID?
  private let authenticate: @MainActor (StudyCredentials) async throws -> StudySignInAccount

  public init(
    forcedEmail: String? = nil, allowsPassword: Bool = false,
    authenticate: @escaping @MainActor (StudyCredentials) async throws -> StudySignInAccount
  ) {
    self.forcedEmail = forcedEmail
    self.email = forcedEmail ?? ""
    self.allowsPassword = allowsPassword
    self.authenticate = authenticate
  }

  public var canSubmit: Bool {
    !isBusy
      && (method == .token
        ? !normalizedToken.isEmpty : !(forcedEmail ?? email).isEmpty && !password.isEmpty)
  }
  private var normalizedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

  public func switchMethod() {
    guard allowsPassword, !isBusy else { return }
    method = method == .token ? .password : .token
    error = nil
    isHibernating = false
  }

  public func submit() async -> StudySignInAccount? {
    guard canSubmit else { return nil }
    let id = UUID()
    request = id
    isBusy = true
    error = nil
    isHibernating = false
    let credentials: StudyCredentials =
      method == .token
      ? .token(normalizedToken)
      : .password(email: forcedEmail ?? email, password: password)
    defer {
      if request == id {
        request = nil
        isBusy = false
      }
    }
    do {
      let result = try await authenticate(credentials)
      guard request == id, !Task.isCancelled else { return nil }
      return result
    } catch {
      guard request == id, !Task.isCancelled, !(error is CancellationError) else { return nil }
      self.error = error.localizedDescription
      if case StudySignInError.hibernating = error { isHibernating = true }
      return nil
    }
  }

  public func cancel() {
    request = nil
    isBusy = false
    token = ""
    password = ""
  }
}
