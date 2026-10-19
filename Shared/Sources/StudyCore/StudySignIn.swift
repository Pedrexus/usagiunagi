import Foundation
import Observation

public enum StudySignInError: LocalizedError, Equatable {
  case hibernating
  case accountMismatch, accountChanged
  case message(String)
  public var errorDescription: String? {
    switch self {
    case .hibernating:
      "Your WaniKani account is hibernating. Sign in on the WaniKani website to reactivate it."
    case .accountMismatch:
      "This token does not match the saved WaniKani account. Your existing token and saved work have not been changed."
    case .accountChanged:
      "The saved account changed while signing in. Try again. Your token has not been replaced."
    case .message(let message): message
    }
  }
}

@MainActor @Observable public final class StudySignIn {
  public var token = ""
  public let forcedEmail: String?
  public private(set) var isBusy = false
  public private(set) var error: String?
  public private(set) var isHibernating = false
  private var request: UUID?
  private var authentication: Task<Void, any Error>?
  private let authenticate: @MainActor (String) async throws -> Void

  public init(
    forcedEmail: String? = nil, authenticate: @escaping @MainActor (String) async throws -> Void
  ) {
    self.forcedEmail = forcedEmail
    self.authenticate = authenticate
  }
  public var canSubmit: Bool { !isBusy && !normalizedToken.isEmpty }
  private var normalizedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

  public func submit() async -> String? {
    guard canSubmit, !Task.isCancelled else { return nil }
    let id = UUID()
    let token = normalizedToken
    request = id
    isBusy = true
    error = nil
    isHibernating = false
    let operation = Task { try await authenticate(token) }
    authentication = operation
    defer {
      if request == id {
        request = nil
        authentication = nil
        isBusy = false
      }
    }
    do {
      try await withTaskCancellationHandler {
        try await operation.value
      } onCancel: {
        operation.cancel()
      }
      guard request == id, !Task.isCancelled else { return nil }
      return token
    } catch {
      guard request == id, !Task.isCancelled, !(error is CancellationError) else { return nil }
      self.error = error.localizedDescription
      if case StudySignInError.hibernating = error { isHibernating = true }
      return nil
    }
  }
  public func cancel() {
    authentication?.cancel()
    authentication = nil
    request = nil
    isBusy = false
    token = ""
    error = nil
    isHibernating = false
  }
}
