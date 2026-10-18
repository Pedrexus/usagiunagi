// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

// swiftlint:disable sorted_imports
import Foundation
import UIKit

// swiftlint:disable superfluous_disable_command
// swiftlint:disable file_length

// MARK: - Storyboard Segues

// swiftlint:disable explicit_type_interface identifier_name line_length type_body_length type_name
internal enum StoryboardSegue {
  internal enum LessonPicker: String, SegueType {
    case startCustomLessons
  }
  internal enum Main: String, SegueType {
    case embedTabBar
    case katakanaCharacterPractice
    case settings
    case showAll
    case showExcluded
    case showLessonPicker
    case showRemaining
    case startAllLeechReviews
    case startAlreadyPassedApprenticeReviews
    case startBurnedItemReviews
    case startLessons
    case startRecentLessonReviews
    case startRecentMistakeReviews
    case startReviews
    case tableForecast
    case viewItemsInSrsCategory
  }
  internal enum Review: String, SegueType {
    case reviewSummary
    case subjectDetails
  }
}
// swiftlint:enable explicit_type_interface identifier_name line_length type_body_length type_name

// MARK: - Implementation Details

internal protocol SegueType: RawRepresentable {}

internal extension UIViewController {
  func perform<S: SegueType>(segue: S, sender: Any? = nil) where S.RawValue == String {
    let identifier = segue.rawValue
    performSegue(withIdentifier: identifier, sender: sender)
  }
}

internal extension SegueType where RawValue == String {
  init?(_ segue: UIStoryboardSegue) {
    guard let identifier = segue.identifier else { return nil }
    self.init(rawValue: identifier)
  }
}
