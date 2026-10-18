// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyPersistence
import StudyUI
import SwiftUI
import UIKit
import WaniKaniAPI

final class DeveloperOptionsViewController: UIHostingController<DeveloperSettingsContent>,
  TKMViewController
{
  init(services: TKMServices) {
    #if DEBUG
      let fixture = Screenshotter.developerFixture()
      let database = fixture ?? LocalCachingClient.databaseUrl()
      let isFixture = fixture != nil
      if isFixture { services.client.baseUrl = Settings.apiBaseUrl }
    #else
      let database = LocalCachingClient.databaseUrl()
      let isFixture = false
    #endif
    super.init(
      rootView: DeveloperSettingsContent(
        services: services, database: database,
        clearAvatarCache: {
          guard !isFixture else { return }
          try await services.legacyAvatars.clear()
          NotificationCenter.default.post(name: .avatarCacheCleared, object: nil)
        }))
  }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(services:)") }
  var canSwipeToGoBack: Bool { true }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }
}

struct DeveloperSettingsContent: View {
  let services: TKMServices
  let database: URL
  let clearAvatarCache: @MainActor () async throws -> Void
  @ArchivedPreference(Settings.$apiBaseUrl) private var endpoint: String
  var body: some View {
    DeveloperSettingsView(
      endpoint: Binding(
        get: { endpoint },
        set: {
          endpoint = $0
          services.client.baseUrl = $0
        }), defaultEndpoint: WaniKaniAPIClient.defaultBaseUrl,
      archive: SQLiteDiagnosticArchive(source: database),
      clearAvatarCache: clearAvatarCache)
  }
}
