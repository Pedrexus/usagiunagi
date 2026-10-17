import StudyCore
import SwiftUI

/// Native hosts share AppStorage observation without replacing legacy iOS preference keys.
@propertyWrapper public struct StoredReviewPreferences: DynamicProperty {
  @AppStorage("native.reviewPreferences") private var data = Data()
  public init() {}
  public var wrappedValue: ReviewPreferences {
    (try? JSONDecoder().decode(ReviewPreferences.self, from: data)) ?? .init()
  }
  public var projectedValue: Self { self }
  public var colorScheme: ColorScheme? {
    switch wrappedValue.appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
  public func applyChanges(from old: ReviewPreferences, to new: ReviewPreferences) throws {
    var current = wrappedValue
    current.applyChanges(from: old, to: new)
    data = try JSONEncoder().encode(current)
  }
}
