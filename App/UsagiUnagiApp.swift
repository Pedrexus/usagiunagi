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
        LegacyStudyWindow(services: appDelegate.services, appDelegate: appDelegate)
      #else
        StudyRootView(
          model: services.model, appName: AppIdentity.name, appearance: services.appearance,
          notice: services.notice
        )
        .environment(services.fonts).environment(services.audio).environment(
          services.lessonSettings
        )
        .defaultAppStorage(services.defaults)
        .frame(minWidth: 640, minHeight: 500)
        .task {
          if ProcessInfo.processInfo.arguments.contains("--sample-data") {
            services.model.loadSample()
          } else {
            await services.model.restore()
          }
        }
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1120, height: 800)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(StudyAppAssembly.isReviewFixture ? .disabled : .automatic)
      .commands {
        CommandGroup(after: .newItem) {
          Button("Refresh WaniKani") { Task { await services.model.refresh() } }
          .keyboardShortcut("r")
          .disabled(services.model.isSyncing || services.model.snapshot?.isSample != false)
        }
      }
    #endif
  }
}
