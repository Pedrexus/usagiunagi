#if DEBUG
  import StudyCore

  /// UI fixtures never prompt, schedule system alerts or change the app badge.
  @MainActor enum NotificationFixture {
    static var client: StudyNotificationClient {
      .init(
        status: { .authorized(Set(NotificationPreference.allCases)) }, request: {},
        pending: { [] }, remove: { _ in }, badge: { _ in }, add: { _ in })
    }
  }
#endif
