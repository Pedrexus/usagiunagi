import StudyUI
import SwiftUI

/// One native SwiftUI app and service graph for iPhone, iPad and Mac.
@main struct UsagiUnagiApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var owner = StudyApplicationOwner()
  #if os(iOS) && DEBUG
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif
  var body: some Scene {
    WindowGroup(id: "study") {
      #if os(iOS) && DEBUG
        if Screenshotter.isActive {
          if let fixture = appDelegate.legacyFixtureServices {
            LegacyStudyWindow(services: fixture)
          } else {
            ProgressView()
          }
        } else {
          nativeWindow
        }
      #else
        nativeWindow
      #endif
    }
    #if os(iOS)
      .backgroundTask(.appRefresh(StudyApplicationOwner.refreshIdentifier)) {
        [owner, backgroundPermitted] in
        guard backgroundPermitted else { return }
        StudyApplicationOwner.scheduleBackgroundRefresh()
        _ = await owner.refreshInBackground()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { StudyApplicationOwner.scheduleBackgroundRefresh() }
      }
    #endif
    #if os(macOS)
      .defaultSize(width: 1120, height: 800)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(StudyAppAssembly.isReviewFixture ? .disabled : .automatic)
      .commands {
        CommandGroup(after: .newItem) {
          Button("Refresh WaniKani") {
            Task {
              guard let services = owner.services else { return }
              await services.model.refresh()
              await services.automaticSync.wake()
            }
          }.keyboardShortcut("r")
          .disabled(
            owner.services?.model.isSyncing != false
              || owner.services?.model.snapshot?.isSample != false)
        }
      }
    #endif
  }
  private var backgroundPermitted: Bool {
    #if os(iOS) && DEBUG
      !Screenshotter.isActive && !StudyAppAssembly.isReviewFixture
    #else
      true
    #endif
  }
  private var nativeWindow: some View {
    StudyApplicationWindow(owner: owner)
      #if os(macOS)
        .frame(minWidth: 640, minHeight: 500)
      #endif
  }
}
