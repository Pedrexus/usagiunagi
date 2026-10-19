// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyPersistence
import StudyUI
import SwiftUI
import WaniKaniAPI

struct DeveloperSettingsContent: View {
  let services: TKMServices
  let database: URL
  let clearAvatarCache: @MainActor () async throws -> Void
  @ArchivedPreference(Settings.$apiBaseUrl) private var endpoint: String
  init(services: TKMServices) {
    self.services = services
    #if DEBUG
      let fixture = Screenshotter.developerFixture()
      database = fixture ?? LocalCachingClient.databaseUrl()
      let isFixture = fixture != nil
      if isFixture { services.client.baseUrl = Settings.apiBaseUrl }
    #else
      database = LocalCachingClient.databaseUrl()
      let isFixture = false
    #endif
    clearAvatarCache = {
      guard !isFixture else { return }
      try await services.legacyAvatars.clear()
      NotificationCenter.default.post(name: .avatarCacheCleared, object: nil)
    }
  }
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
