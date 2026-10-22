import Foundation

/// Frozen interpretation metadata stored in V1 import receipts; no runtime import behavior.
public struct StudyLegacyMistakeContext: Codable, Equatable, Sendable {
  public let locale: Locale
  public let calendar: Calendar
  public init(locale: Locale, calendar: Calendar) {
    self.locale = locale
    self.calendar = calendar
  }
}
