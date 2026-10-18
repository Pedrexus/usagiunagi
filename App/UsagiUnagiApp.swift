import StudyUI
import SwiftUI

/// One native app target and entry point for iPhone, iPad and Mac.
@main
struct UsagiUnagiApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #else
    @State private var model = StudyAppAssembly.makeModel()
  #endif

  var body: some Scene {
    WindowGroup(id: "study") {
      #if os(iOS)
        LegacyStudyWindow(services: appDelegate.services, appDelegate: appDelegate)
      #else
        StudyRoot(store: model)
          .defaultAppStorage(StudyAppAssembly.reviewDefaults)
          .frame(minWidth: 640, minHeight: 500)
          .task {
            if ProcessInfo.processInfo.arguments.contains("--sample-data") {
              model.loadSample()
            } else {
              await model.restore()
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
          Button("Refresh WaniKani") { Task { await model.refresh() } }
          .keyboardShortcut("r")
          .disabled(model.isSyncing || model.snapshot?.isSample != false)
        }
      }
    #endif
  }
}
