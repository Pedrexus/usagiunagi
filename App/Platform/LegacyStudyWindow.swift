import SwiftUI
import UIKit

/// Temporary presentation adapter while the existing iOS writer is replaced safely.
struct LegacyStudyWindow: View {
  let services: TKMServices
  @Environment(\.scenePhase) private var phase
  @State private var coordinator: LegacyStudyCoordinator?
  @State private var pendingURLs: [URL] = []
  @State private var pendingActivities: [String] = []

  var body: some View {
    Group {
      if let coordinator {
        LegacyNavigationHost(coordinator: coordinator)
          .ignoresSafeArea()
          .onAppear { coordinator.becomeActive() }
      } else {
        ProgressView()
      }
    }
    .task {
      guard coordinator == nil else { return }
      let value = LegacyStudyCoordinator(services: services)
      coordinator = value
      for url in pendingURLs { value.openURL(url) }
      pendingURLs.removeAll()
      for type in pendingActivities { value.startUserActivity(type: type) }
      pendingActivities.removeAll()
    }
    .onOpenURL { url in
      open(url)
    }
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
      if let url = activity.webpageURL { open(url) }
    }
    .onContinueUserActivity(SiriShortcutHelper.ShortcutType.reviews.rawValue) { activity in
      start(activity.activityType)
    }
    .onContinueUserActivity(SiriShortcutHelper.ShortcutType.lessons.rawValue) { activity in
      start(activity.activityType)
    }
    .onChange(of: phase) { previous, value in
      if value == .active {
        coordinator?.becomeActive()
      } else if previous == .active {
        coordinator?.resignActive()
      }
    }
  }
  private func open(_ url: URL) {
    if let coordinator { coordinator.openURL(url) } else { pendingURLs.append(url) }
  }
  private func start(_ type: String) {
    if let coordinator {
      coordinator.startUserActivity(type: type)
    } else {
      pendingActivities.append(type)
    }
  }
}

private struct LegacyNavigationHost: UIViewControllerRepresentable {
  let coordinator: LegacyStudyCoordinator
  func makeUIViewController(context: Context) -> UINavigationController {
    coordinator.navigationController
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
