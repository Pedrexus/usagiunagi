import StudyCore
import SwiftUI

/// Native hosts share AppStorage observation without replacing legacy iOS preference keys.
@propertyWrapper struct StoredReviewPreferences: DynamicProperty {
  @AppStorage("native.reviewPreferences") private var data = Data()
  @Environment(\.studyICloudPreferences) private var iCloud
  var wrappedValue: ReviewPreferences {
    (try? JSONDecoder().decode(ReviewPreferences.self, from: data)) ?? .init()
  }
  var projectedValue: Self { self }
  var colorScheme: ColorScheme? {
    switch wrappedValue.appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
  func applyChanges(from old: ReviewPreferences, to new: ReviewPreferences) throws {
    let previous = wrappedValue
    var current = previous
    current.applyChanges(from: old, to: new)
    data = try JSONEncoder().encode(current)
    iCloud?.recordChanges(from: previous, to: current)
  }
}
