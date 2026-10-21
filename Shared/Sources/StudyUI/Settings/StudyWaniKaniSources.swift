import SwiftUI

/// Source choices are separate from the preference values captured in historical handoffs.
public struct StudyWaniKaniSources: DynamicProperty {
  @AppStorage("native.waniKani.audio") var audio = false
  @AppStorage("native.waniKani.reviewOrder") var reviewOrder = false
  @AppStorage("native.waniKani.srsFeedback") var srsFeedback = false
  @AppStorage("native.waniKani.lessonBatch") var lessonBatch = false

  /// Local initialization only. Never publishes an iCloud edit or writes to WaniKani.
  public static func prepare(defaults: UserDefaults) {
    for (key, existing) in [
      ("audio", "native.reviewPreferences"), ("reviewOrder", "native.reviewPreferences"),
      ("srsFeedback", "native.reviewPreferences"), ("lessonBatch", "native.lessonPreferences"),
    ] {
      let destination = "native.waniKani." + key
      if defaults.object(forKey: destination) == nil {
        defaults.set(defaults.object(forKey: existing) == nil, forKey: destination)
      }
    }
  }
}
