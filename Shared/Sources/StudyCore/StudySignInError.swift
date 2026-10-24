import Foundation

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
