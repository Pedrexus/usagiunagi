#if DEBUG
  import StudyCore
  import StudyUI

  /// UI fixtures never prompt, schedule system alerts or change the app badge.
  @MainActor enum NotificationFixture {
    #if os(iOS)
      static var companion: StudyCompanionDelivery? {
        Screenshotter.isActive ? StudyCompanionDelivery(send: { _, _ in false }) : nil
      }
    #endif
    static var client: StudyNotificationClient {
      .init(
        status: { .authorized(Set(NotificationPreference.allCases)) }, request: {},
        pending: { [] }, remove: { _ in }, badge: { _ in }, add: { _ in })
    }
  }
#endif
