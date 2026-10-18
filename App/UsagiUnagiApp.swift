import SwiftUI

/// One native app target and entry point for iPhone, iPad and Mac.
@main
struct UsagiUnagiApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #else
    @State private var model = StudyAppState()
  #endif

  var body: some Scene {
    WindowGroup(id: "study") {
      #if os(iOS)
        LegacyStudyWindow(services: appDelegate.services, appDelegate: appDelegate)
      #else
        StudyRoot(store: model)
          .defaultAppStorage(StudyAppState.reviewDefaults)
          .frame(minWidth: 640, minHeight: 500)
          .task { await model.restore() }
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1120, height: 800)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(model.isReviewFixture ? .disabled : .automatic)
      .commands {
        CommandGroup(after: .newItem) {
          Button("Refresh WaniKani") { Task { await model.refresh() } }
          .keyboardShortcut("r")
          .disabled(model.isSyncing || model.snapshot?.isSample != false)
        }
      }
    #endif
  }
}
