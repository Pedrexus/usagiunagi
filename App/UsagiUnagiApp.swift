import StudyCore
import StudyUI
import SwiftUI

/// One native app target and entry point for iPhone, iPad and Mac.
@main
struct UsagiUnagiApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #else
    @State private var services = StudyAppAssembly.make()
  #endif

  var body: some Scene {
    WindowGroup(id: "study") {
      #if os(iOS)
        LegacyStudyWindow(services: appDelegate.services)
      #else
        StudyRootView(
          model: services.model, automaticSync: services.automaticSync, appName: AppIdentity.name,
          appearance: services.appearance,
          notice: services.notice,
          notifications: services.notifications
        )
        .environment(services.fonts).environment(services.audio).environment(
          services.lessonSettings
        )
        .environment(services.subjectSettings)
        .defaultAppStorage(services.defaults)
        .frame(minWidth: 640, minHeight: 500)
        .task {
          await services.model.restore()
        }
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1120, height: 800)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(StudyAppAssembly.isReviewFixture ? .disabled : .automatic)
      .commands {
        CommandGroup(after: .newItem) {
          Button("Refresh WaniKani") {
            Task {
              await services.model.refresh()
              await services.automaticSync.wake()
            }
          }
          .keyboardShortcut("r")
          .disabled(services.model.isSyncing || services.model.snapshot?.isSample != false)
        }
      }
    #endif
  }
}
