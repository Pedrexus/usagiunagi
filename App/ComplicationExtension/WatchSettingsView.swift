// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Combine
import Foundation
import SwiftUI

/// Retains the installed WatchKit scene and extension identity while SwiftUI owns its content.
final class SettingsController: WKHostingController<WatchSettingsView> {
  override var body: WatchSettingsView { WatchSettingsView() }
}

struct WatchSettingsView: View {
  @AppStorage(WatchCompanionCache.sourceKey) private var source = ComplicationDataSource.reviews
    .rawValue
  @State private var snapshot = WatchCompanionCache.sharedInstance.state.snapshot

  var body: some View {
    NavigationStack {
      TimelineView(.periodic(from: Date(), by: 60)) { context in
        Form {
          Section("Data Source") {
            Picker("Show", selection: selection) {
              Text("Review Counts").tag(ComplicationDataSource.reviews.rawValue)
              Text("Level").tag(ComplicationDataSource.level.rawValue)
              if source == ComplicationDataSource.legacyCharacter.rawValue {
                Text("Kanji — unavailable")
                  .tag(ComplicationDataSource.legacyCharacter.rawValue)
                  .disabled(true)
              }
            }
            if source == ComplicationDataSource.legacyCharacter.rawValue {
              Text("Choose Review Counts or Level to show your study data.")
                .font(.footnote)
            }
          }
          Section("Last Updated") {
            if let snapshot {
              Text(snapshot.sentAt, style: .relative)
              if context.date >= snapshot.expiresAt {
                Label(
                  "The data on this watch is stale. Open the app on your phone to update.",
                  systemImage: "exclamationmark.triangle")
              }
            } else {
              Text("No data. Open the app on your phone to update.")
            }
          }
        }
      }
      .navigationTitle("Settings")
    }
    .onAppear { snapshot = WatchCompanionCache.sharedInstance.state.snapshot }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UserDefaults.didChangeNotification, object: UserDefaults.standard
      )
      .receive(on: RunLoop.main)
    ) { _ in
      snapshot = WatchCompanionCache.sharedInstance.state.snapshot
    }
  }

  private var selection: Binding<Int> {
    Binding(
      get: {
        ComplicationDataSource(rawValue: source)?.rawValue
          ?? ComplicationDataSource.reviews.rawValue
      },
      set: { value in
        guard value != source else { return }
        source = value
        WatchHelper.reloadComplications()
      })
  }
}
