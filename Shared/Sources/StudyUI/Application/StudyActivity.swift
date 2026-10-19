import CoreSpotlight
import Foundation
import Intents
import StudyCore
import UniformTypeIdentifiers

extension StudyActivity {
  /// Preserve the existing search/prediction identity while native scenes own presentation.
  public func configure(_ activity: NSUserActivity) {
    activity.persistentIdentifier = NSUserActivityPersistentIdentifier(rawValue)
    activity.isEligibleForSearch = true
    #if os(iOS)
      activity.isEligibleForPrediction = true
    #endif
    let title = self == .reviews ? "Start Wanikani Reviews" : "Start Wanikani Lessons"
    activity.title = title
    activity.suggestedInvocationPhrase = title
    let attributes = CSSearchableItemAttributeSet(contentType: .item)
    attributes.contentDescription =
      self == .reviews ? "Keep it up and burn every one" : "Learn something new"
    activity.contentAttributeSet = attributes
  }
}
