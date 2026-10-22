import SwiftUI

/// One native SwiftUI app and service graph for iPhone, iPad and Mac.
@main struct UsagiUnagiApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var owner: StudyApplicationOwner
  init() {
    let owner = StudyApplicationOwner()
    _owner = State(initialValue: owner)
    #if os(iOS)
      if !StudyAppAssembly.isReviewFixture {
        WatchHelper.sharedInstance.reviewRequest = { [weak owner] request in
          await owner?.receiveWatchReview(request)
            ?? .init(
              runID: request.runID, outcome: .unavailable,
              feedback: "Open the app on your iPhone first.")
        }
      }
    #endif
  }
  var body: some Scene {
    WindowGroup(id: "study") {
      StudyApplicationWindow(owner: owner)
    }
    .defaultSize(width: 1120, height: 800)
    #if os(iOS)
      .backgroundTask(.appRefresh(StudyApplicationOwner.refreshIdentifier)) {
        [owner, backgroundPermitted] in
        guard backgroundPermitted else { return }
        await StudyApplicationOwner.scheduleBackgroundRefresh()
        _ = await owner.refreshInBackground()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background && backgroundPermitted {
          Task { await StudyApplicationOwner.scheduleBackgroundRefresh() }
        }
      }
    #endif
    #if os(macOS)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(StudyAppAssembly.isReviewFixture ? .disabled : .automatic)
    #endif
    .commands {
      CommandGroup(after: .newItem) {
        Button("Refresh WaniKani") {
          Task {
            guard let services = owner.services else { return }
            await services.model.refresh()
            await services.automaticSync.wake()
          }
        }.keyboardShortcut("r", modifiers: [.command, .shift])
          .disabled(
            owner.services?.model.isSyncing != false
              || owner.services?.model.snapshot?.isSample != false)
      }
    }
  }
  private var backgroundPermitted: Bool {
    #if DEBUG
      !StudyAppAssembly.isReviewFixture
    #else
      true
    #endif
  }
}
